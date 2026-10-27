// Adversarial security-rules tests: what an attacker with a valid account can
// try against the published rules. Users: alice (A) and bob (B) talk to each
// other; carol (C) is an outsider; "blocked" scenarios use the block list.
// Run in CI by the "rules" job (Firebase emulator).
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, test } from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  limit,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
  writeBatch,
} from 'firebase/firestore';

let env;
const db = (uid) => env.authenticatedContext(uid).firestore();
const HOUR = 3600 * 1000;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-aduchat',
    firestore: { rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8') },
  });
});

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const f = ctx.firestore();
    for (const uid of ['alice', 'bob', 'carol']) {
      await setDoc(doc(f, 'users', uid), {
        uid, displayName: uid, displayNameLower: uid, about: '', createdAt: new Date(), updatedAt: new Date(),
      });
      await setDoc(doc(f, 'users', uid, 'private', 'account'), { email: `${uid}@example.com` });
      await setDoc(doc(f, 'users', uid, 'devices', `token-${uid}`), { platform: 'android' });
      await setDoc(doc(f, 'directory', uid), {
        uid, displayName: uid, displayNameLower: uid, username: uid, usernameLower: uid, updatedAt: new Date(),
      });
    }
    await setDoc(doc(f, 'chats', 'group1'), {
      type: 'group', name: 'Family', createdBy: 'alice', members: ['alice', 'bob'], admins: ['alice'],
      onlyAdminsCanSend: false, onlyAdminsEditInfo: false, updatedAt: new Date(),
    });
  });
});

after(async () => {
  await env.cleanup();
});

function msg(sender, receiver, extra = {}) {
  const m = {
    senderId: sender, type: 'text', text: 'hi', clientCreatedAt: new Date(), createdAt: serverTimestamp(), ...extra,
  };
  if (receiver) Object.assign(m, { receiverId: receiver, status: 'sent' });
  return m;
}

function chatSummary(sender, members, id, extra = {}) {
  return {
    type: 'direct', members, lastMessage: 'hi', lastMessageType: 'text', lastSenderId: sender,
    lastMessageAt: new Date(), lastMessageId: id, updatedAt: serverTimestamp(), ...extra,
  };
}

/** The app's write: chat summary + message in one batch. */
function sendDirect(sender, receiver, id, { chatId, message = {}, summary = {} } = {}) {
  const d = db(sender);
  const members = [sender, receiver].sort();
  const cid = chatId || members.join('_');
  const batch = writeBatch(d);
  batch.set(doc(d, 'chats', cid), chatSummary(sender, members, id, summary), { merge: true });
  batch.set(doc(d, 'chats', cid, 'messages', id), msg(sender, receiver, message));
  return batch.commit();
}

const groupMsg = (sender, extra = {}) => ({
  senderId: sender, type: 'text', text: 'hello group', readBy: [],
  clientCreatedAt: new Date(), createdAt: serverTimestamp(), ...extra,
});
const sys = (sender, text) => groupMsg(sender, { type: 'system', text });
const block = (owner, other) =>
  setDoc(doc(db(owner), 'users', owner, 'blocked', other), { uid: other, createdAt: serverTimestamp() });

describe('direct chats: existence and ids, not only id parsing', () => {
  test('baseline: A and B can talk', async () => {
    await assertSucceeds(sendDirect('alice', 'bob', 'm1'));
    await assertSucceeds(sendDirect('bob', 'alice', 'm2'));
  });

  test('a message cannot be written into a direct chat that does not exist', async () => {
    await assertFails(setDoc(doc(db('alice'), 'chats', 'alice_bob', 'messages', 'x'), msg('alice', 'bob')));
  });

  test('unsorted, empty-part and multi-part ids are refused', async () => {
    await assertFails(sendDirect('alice', 'bob', 'm1', { chatId: 'bob_alice' }));
    for (const id of ['alice_', '_alice', 'alice_bob_carol']) {
      await assertFails(setDoc(doc(db('alice'), 'chats', id), chatSummary('alice', ['alice', 'bob'], 'm1')));
    }
  });

  test('a direct chat with an account that does not exist is refused', async () => {
    await assertFails(sendDirect('alice', 'ghost', 'm1'));
  });

  test('a chat summary cannot be created or changed without a real message', async () => {
    await assertFails(setDoc(doc(db('alice'), 'chats', 'alice_bob'), chatSummary('alice', ['alice', 'bob'], 'nope')));
    await sendDirect('alice', 'bob', 'm1');
    await assertFails(updateDoc(doc(db('alice'), 'chats', 'alice_bob'), {
      lastMessage: 'fake preview', lastSenderId: 'alice', lastMessageId: 'does-not-exist',
    }));
  });

  test('a member cannot rewrite the member list or add unknown fields', async () => {
    await sendDirect('alice', 'bob', 'm1');
    await assertFails(updateDoc(doc(db('alice'), 'chats', 'alice_bob'), { members: ['alice', 'carol'] }));
    await assertFails(updateDoc(doc(db('alice'), 'chats', 'alice_bob'), { verified: true }));
  });

  test('the outsider C cannot read, list or write the chat', async () => {
    await sendDirect('alice', 'bob', 'm1');
    await assertFails(getDoc(doc(db('carol'), 'chats', 'alice_bob')));
    await assertFails(getDocs(collection(db('carol'), 'chats', 'alice_bob', 'messages')));
    await assertFails(getDocs(query(collection(db('carol'), 'chats'), where('members', 'array-contains', 'alice'))));
    await assertFails(setDoc(doc(db('carol'), 'chats', 'alice_bob', 'messages', 'c1'), msg('carol', 'bob')));
    await assertFails(updateDoc(doc(db('carol'), 'chats', 'alice_bob'), { 'typing.carol': new Date() }));
  });

  test('messages cannot be addressed to someone outside the chat', async () => {
    await sendDirect('alice', 'bob', 'm1');
    await assertFails(setDoc(doc(db('alice'), 'chats', 'alice_bob', 'messages', 'm2'), msg('alice', 'carol')));
  });

  test('client time cannot be set in the future (pinning) and server time is required', async () => {
    await assertFails(sendDirect('alice', 'bob', 'm1', { message: { clientCreatedAt: new Date(Date.now() + 48 * HOUR) } }));
    await assertFails(sendDirect('alice', 'bob', 'm1', { message: { createdAt: new Date() } }));
    // an old client time is fine (message queued while offline)
    await assertSucceeds(sendDirect('alice', 'bob', 'm1', { message: { clientCreatedAt: new Date(Date.now() - 72 * HOUR) } }));
  });

  test('system messages are not allowed in direct chats', async () => {
    await assertFails(sendDirect('alice', 'bob', 'm1', { message: { type: 'system', text: 'admin_added:alice' } }));
  });

  test('message status and receipts cannot be faked by the sender', async () => {
    await assertFails(sendDirect('alice', 'bob', 'm1', { message: { status: 'read' } }));
    await sendDirect('alice', 'bob', 'm1');
    await assertFails(updateDoc(doc(db('alice'), 'chats', 'alice_bob', 'messages', 'm1'), { status: 'read' }));
  });
});

describe('blocking is enforced in both directions', () => {
  test('a blocked user cannot start a chat, message, type, preview, attach or call', async () => {
    await sendDirect('alice', 'bob', 'm1');
    await block('bob', 'alice');
    const chat = doc(db('alice'), 'chats', 'alice_bob');
    await assertFails(sendDirect('alice', 'bob', 'm2'));
    await assertFails(updateDoc(chat, { 'typing.alice': new Date() }));
    // the chat preview (shown in B's chat list) cannot be used to bypass the block
    await assertFails(updateDoc(chat, { lastMessage: 'still here', lastSenderId: 'alice', lastMessageId: 'm1' }));
    await assertFails(setDoc(doc(db('alice'), 'chats', 'alice_bob', 'blobs', 'b1'), {
      senderId: 'alice', data: 'aGVsbG8=', mime: 'image/jpeg', size: 5, createdAt: serverTimestamp(),
    }));
    await assertFails(setDoc(doc(db('alice'), 'calls', 'c1'), {
      callerId: 'alice', calleeId: 'bob', members: ['alice', 'bob'], type: 'audio', status: 'ringing',
      createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
    }));
  });

  test('a blocked user can still clear their own unread counter', async () => {
    await sendDirect('bob', 'alice', 'm1');
    await block('bob', 'alice');
    await assertSucceeds(updateDoc(doc(db('alice'), 'chats', 'alice_bob'), { 'unread.alice': 0 }));
    await assertFails(updateDoc(doc(db('alice'), 'chats', 'alice_bob'), { 'unread.bob': 0 }));
  });

  test('the blocker cannot message the blocked person either', async () => {
    await sendDirect('alice', 'bob', 'm1');
    await block('bob', 'alice');
    await assertFails(sendDirect('bob', 'alice', 'm2'));
  });

  test('a new chat cannot be created with someone who blocked you', async () => {
    await block('carol', 'alice');
    await assertFails(sendDirect('alice', 'carol', 'm1'));
  });

  test('nobody can read or edit someone else\'s block list', async () => {
    await block('bob', 'alice');
    await assertFails(getDoc(doc(db('alice'), 'users', 'bob', 'blocked', 'alice')));
    await assertFails(deleteDoc(doc(db('alice'), 'users', 'bob', 'blocked', 'alice')));
  });
});

describe('groups: admin-only posting and system-message exceptions', () => {
  test('when only admins can send, a member cannot hide a message as "system"', async () => {
    await env.withSecurityRulesDisabled((ctx) => updateDoc(doc(ctx.firestore(), 'chats', 'group1'), { onlyAdminsCanSend: true }));
    const m = (id, data) => setDoc(doc(db('bob'), 'chats', 'group1', 'messages', id), data);
    await assertFails(m('g1', groupMsg('bob')));
    await assertFails(m('g2', sys('bob', 'buy cheap followers at example.com')));
    await assertFails(m('g3', sys('bob', 'added:carol')));
    // leaving is always announced
    await assertSucceeds(m('g4', sys('bob', 'left')));
    await assertSucceeds(setDoc(doc(db('alice'), 'chats', 'group1', 'messages', 'g5'), groupMsg('alice')));
  });

  test('members cannot forge admin events; unknown events are refused even for admins', async () => {
    const m = (uid, id, text) => setDoc(doc(db(uid), 'chats', 'group1', 'messages', id), sys(uid, text));
    await assertFails(m('bob', 's1', 'admin_added:bob'));
    await assertFails(m('bob', 's2', 'removed:alice'));
    await assertFails(m('alice', 's3', 'hacked'));
    await assertSucceeds(m('alice', 's4', 'admin_added:bob'));
  });

  test('rename notices follow the "only admins edit info" setting', async () => {
    await assertSucceeds(setDoc(doc(db('bob'), 'chats', 'group1', 'messages', 'r1'), sys('bob', 'renamed:New')));
    await env.withSecurityRulesDisabled((ctx) => updateDoc(doc(ctx.firestore(), 'chats', 'group1'), { onlyAdminsEditInfo: true }));
    await assertFails(setDoc(doc(db('bob'), 'chats', 'group1', 'messages', 'r2'), sys('bob', 'renamed:Other')));
    await assertFails(updateDoc(doc(db('bob'), 'chats', 'group1'), { name: 'Other', updatedAt: serverTimestamp() }));
  });

  test('system messages cannot be "deleted for everyone" to hide group history', async () => {
    await setDoc(doc(db('alice'), 'chats', 'group1', 'messages', 's1'), sys('alice', 'added:bob'));
    await assertFails(updateDoc(doc(db('alice'), 'chats', 'group1', 'messages', 's1'), {
      deleted: true, text: '', deletedAt: serverTimestamp(),
    }));
  });

  test('group messages cannot carry fake read receipts or direct-chat fields', async () => {
    const m = (id, extra) => setDoc(doc(db('bob'), 'chats', 'group1', 'messages', id), groupMsg('bob', extra));
    await assertFails(m('x1', { readBy: ['alice'] }));
    await assertFails(m('x2', { status: 'read' }));
    await assertFails(m('x3', { receiverId: 'alice' }));
  });

  test('the outsider C cannot read, post, join or rename', async () => {
    await assertFails(getDoc(doc(db('carol'), 'chats', 'group1')));
    await assertFails(setDoc(doc(db('carol'), 'chats', 'group1', 'messages', 'c1'), groupMsg('carol')));
    await assertFails(updateDoc(doc(db('carol'), 'chats', 'group1'), { members: ['alice', 'bob', 'carol'] }));
    await assertFails(updateDoc(doc(db('carol'), 'chats', 'group1'), { name: 'pwned' }));
  });

  test('a member cannot promote themselves or remove others', async () => {
    await assertFails(updateDoc(doc(db('bob'), 'chats', 'group1'), { admins: ['alice', 'bob'] }));
    await assertFails(updateDoc(doc(db('bob'), 'chats', 'group1'), { members: ['bob'], admins: [] }));
  });

  test('admins cannot add unknown fields, oversize names or more than 256 members', async () => {
    const g = doc(db('alice'), 'chats', 'group1');
    await assertFails(updateDoc(g, { verifiedBadge: true }));
    await assertFails(updateDoc(g, { name: 'x'.repeat(61) }));
    const many = Array.from({ length: 257 }, (_, i) => `u${i}`).concat(['alice']);
    await assertFails(updateDoc(g, { members: many }));
    await assertSucceeds(updateDoc(g, { name: 'Family 2', updatedAt: serverTimestamp() }));
  });

  test('group ids containing "_" cannot be created as groups', async () => {
    await assertFails(setDoc(doc(db('alice'), 'chats', 'zz_alice'), {
      type: 'group', name: 'x', createdBy: 'alice', members: ['alice', 'bob'], admins: ['alice'],
    }));
  });

  test('a group cannot be created with unknown fields', async () => {
    await assertFails(setDoc(doc(db('alice'), 'chats', 'g2'), {
      type: 'group', name: 'x', createdBy: 'alice', members: ['alice', 'bob'], admins: ['alice'], official: true,
    }));
  });
});

describe('profile privacy and anti-enumeration', () => {
  test('C cannot read A\'s private settings, devices, blocks or call history', async () => {
    for (const path of [['private', 'account'], ['devices', 'token-alice'], ['blocked', 'x'], ['calls', 'x']]) {
      await assertFails(getDoc(doc(db('carol'), 'users', 'alice', ...path)));
    }
    await assertFails(getDocs(collection(db('carol'), 'users', 'alice', 'devices')));
  });

  test('C cannot register a push token or write private data for A', async () => {
    await assertFails(setDoc(doc(db('carol'), 'users', 'alice', 'devices', 'evil'), { platform: 'android' }));
    await assertFails(setDoc(doc(db('carol'), 'users', 'alice', 'private', 'account'), { notifications: {} }));
    await assertFails(updateDoc(doc(db('carol'), 'users', 'alice'), { displayName: 'pwned' }));
  });

  test('C cannot plant fake call history for an unrelated call', async () => {
    await assertFails(setDoc(doc(db('carol'), 'users', 'alice', 'calls', 'fake'), {
      callId: 'fake', peerId: 'carol', type: 'audio', direction: 'incoming', status: 'missed', createdAt: serverTimestamp(),
    }));
  });

  test('the directory can only be searched in small pages, never dumped', async () => {
    const dir = collection(db('carol'), 'directory');
    await assertFails(getDocs(dir));
    await assertFails(getDocs(query(dir, limit(500))));
    await assertSucceeds(getDocs(query(dir, where('usernameLower', '>=', 'al'), where('usernameLower', '<', 'al'), limit(20))));
  });

  test('phone numbers cannot be listed and only your own verified number can be registered', async () => {
    const carol = env.authenticatedContext('carol', { phone_number: '+966500000003' }).firestore();
    await assertFails(getDocs(collection(carol, 'phoneIndex')));
    await assertFails(setDoc(doc(carol, 'phoneIndex', '+252610000001'), { uid: 'carol', updatedAt: serverTimestamp() }));
    await assertSucceeds(setDoc(doc(carol, 'phoneIndex', '+966500000003'), { uid: 'carol', updatedAt: serverTimestamp() }));
  });

  test('signed-out visitors cannot read anything', async () => {
    const anon = env.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(anon, 'users', 'alice')));
    await assertFails(getDoc(doc(anon, 'directory', 'alice')));
    await assertFails(getDoc(doc(anon, 'usernames', 'alice')));
  });
});

describe('calls: signaling integrity', () => {
  const call = (extra = {}) => ({
    callerId: 'alice', calleeId: 'bob', members: ['alice', 'bob'], type: 'audio', status: 'ringing',
    offer: { sdp: 'v=0', type: 'offer' }, offerVersion: 1, createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
    ...extra,
  });

  test('calls to accounts that do not exist are refused', async () => {
    await assertFails(setDoc(doc(db('alice'), 'calls', 'c1'), call({ calleeId: 'ghost', members: ['alice', 'ghost'] })));
  });

  test('a caller who blocked the callee cannot ring them', async () => {
    await block('alice', 'bob');
    await assertFails(setDoc(doc(db('alice'), 'calls', 'c1'), call()));
  });

  test('nobody can start a call on behalf of someone else or include a third member', async () => {
    await assertFails(setDoc(doc(db('carol'), 'calls', 'c1'), call()));
    await assertFails(setDoc(doc(db('alice'), 'calls', 'c2'), call({ members: ['alice', 'bob', 'carol'] })));
  });

  test('oversized or malformed session descriptions are refused', async () => {
    await assertFails(setDoc(doc(db('alice'), 'calls', 'c1'), call({ offer: { sdp: 'x'.repeat(100001), type: 'offer' } })));
    await assertFails(setDoc(doc(db('alice'), 'calls', 'c2'), call({ offer: { sdp: 'v=0', type: 'offer', script: 1 } })));
  });

  test('C cannot read, answer, hang up or inject ICE candidates', async () => {
    await setDoc(doc(db('alice'), 'calls', 'c1'), call());
    await assertFails(getDoc(doc(db('carol'), 'calls', 'c1')));
    await assertFails(updateDoc(doc(db('carol'), 'calls', 'c1'), { status: 'ended' }));
    await assertFails(setDoc(doc(db('carol'), 'calls', 'c1', 'candidates', 'k1'), {
      from: 'carol', candidate: 'candidate:1', sdpMid: '0', sdpMLineIndex: 0, createdAt: serverTimestamp(),
    }));
  });

  test('the callee cannot replace the caller\'s offer; members cannot spoof candidate senders', async () => {
    await setDoc(doc(db('alice'), 'calls', 'c1'), call());
    await assertFails(updateDoc(doc(db('bob'), 'calls', 'c1'), { offer: { sdp: 'evil', type: 'offer' } }));
    await assertFails(setDoc(doc(db('bob'), 'calls', 'c1', 'candidates', 'k1'), {
      from: 'alice', candidate: 'candidate:1', sdpMid: '0', sdpMLineIndex: 0, createdAt: serverTimestamp(),
    }));
    await assertFails(setDoc(doc(db('bob'), 'calls', 'c1', 'candidates', 'k2'), {
      from: 'bob', candidate: 'x'.repeat(2001), sdpMid: '0', sdpMLineIndex: 0, createdAt: serverTimestamp(),
    }));
  });

  test('call records cannot be deleted', async () => {
    await setDoc(doc(db('alice'), 'calls', 'c1'), call());
    await assertFails(deleteDoc(doc(db('alice'), 'calls', 'c1')));
  });
});

describe('inline attachments', () => {
  const blob = (extra = {}) => ({ senderId: 'alice', data: 'aGVsbG8=', mime: 'image/jpeg', size: 5, createdAt: serverTimestamp(), ...extra });

  test('only media types are accepted; executables, HTML and SVG are refused', async () => {
    await sendDirect('alice', 'bob', 'm1');
    const put = (id, extra) => setDoc(doc(db('alice'), 'chats', 'alice_bob', 'blobs', id), blob(extra));
    await assertSucceeds(put('ok1', {}));
    await assertSucceeds(put('ok2', { mime: 'audio/mp4' }));
    for (const mime of ['application/vnd.android.package-archive', 'application/x-msdownload', 'text/html', 'image/svg+xml', 'application/octet-stream']) {
      await assertFails(put(`bad-${mime.length}`, { mime }));
    }
  });

  test('blobs cannot claim an absurd size, be written as someone else, or go into a missing chat', async () => {
    await sendDirect('alice', 'bob', 'm1');
    await assertFails(setDoc(doc(db('alice'), 'chats', 'alice_bob', 'blobs', 'b1'), blob({ size: 50_000_000 })));
    await assertFails(setDoc(doc(db('alice'), 'chats', 'alice_bob', 'blobs', 'b2'), blob({ senderId: 'bob' })));
    await assertFails(setDoc(doc(db('alice'), 'chats', 'alice_carol', 'blobs', 'b3'), blob()));
  });

  test('C cannot read or delete A\'s attachment', async () => {
    await sendDirect('alice', 'bob', 'm1');
    await setDoc(doc(db('alice'), 'chats', 'alice_bob', 'blobs', 'b1'), blob());
    await assertFails(getDoc(doc(db('carol'), 'chats', 'alice_bob', 'blobs', 'b1')));
    await assertFails(deleteDoc(doc(db('carol'), 'chats', 'alice_bob', 'blobs', 'b1')));
    await assertFails(deleteDoc(doc(db('bob'), 'chats', 'alice_bob', 'blobs', 'b1')));
  });
});
