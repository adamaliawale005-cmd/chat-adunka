// Compatibility tests: every Firestore write the CURRENT app makes (the code
// in lib/services on main, the same code installed on phones and served on
// the web), replayed with the same field shapes and sentinel values, must
// still be accepted by the new firestore.rules. If one of these fails, the
// rules would break existing installations.
//
// Source of each write is named in the test title (Dart file and method).
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, test } from 'node:test';

import { assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import {
  addDoc,
  arrayRemove,
  arrayUnion,
  collection,
  deleteDoc,
  deleteField,
  doc,
  getDoc,
  getDocs,
  increment,
  limit,
  orderBy,
  query,
  runTransaction,
  serverTimestamp,
  setDoc,
  Timestamp,
  updateDoc,
  where,
  writeBatch,
} from 'firebase/firestore';

let env;
const PHONE = { alice: '+252610000001', bob: '+252610000002', carol: '+966500000003' };
const db = (uid) => env.authenticatedContext(uid, { phone_number: PHONE[uid] }).firestore();
const DIRECT = 'alice_bob';

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-aduchat',
    firestore: { rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8') },
  });
});

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    for (const uid of ['alice', 'bob', 'carol']) {
      await setDoc(doc(ctx.firestore(), 'users', uid), {
        uid, displayName: uid, displayNameLower: uid, username: uid, usernameLower: uid,
        about: '', createdAt: new Date(), updatedAt: new Date(),
      });
      await setDoc(doc(ctx.firestore(), 'usernames', uid), { uid, createdAt: new Date() });
    }
  });
});

after(async () => {
  await env.cleanup();
});

// ---- ChatService.send (direct and group), same keys and sentinels ----
function send(sender, chat, id, { type = 'text', text = 'hello', attachment, replyTo, forwarded, extra } = {}) {
  const d = db(sender);
  const now = Timestamp.now();
  const batch = writeBatch(d);
  if (extra) extra(batch, d);
  const others = chat.members.filter((m) => m !== sender);
  const summary = {
    lastMessage: text, lastMessageType: type, lastSenderId: sender, lastMessageAt: now, lastMessageId: id,
    updatedAt: serverTimestamp(),
    unread: { ...Object.fromEntries(others.map((o) => [o, increment(1)])), [sender]: 0 },
    typing: { [sender]: deleteField() },
  };
  if (!chat.isGroup) Object.assign(summary, { type: 'direct', members: chat.members });
  batch.set(doc(d, 'chats', chat.id), summary, { merge: true });
  const message = {
    senderId: sender, type, text, clientCreatedAt: now, createdAt: serverTimestamp(),
    ...(attachment ? { attachment } : {}),
    ...(replyTo ? { replyTo } : {}),
    ...(forwarded ? { forwarded: true } : {}),
  };
  if (chat.isGroup) message.readBy = [];
  else Object.assign(message, { receiverId: others[0], status: 'sent' });
  batch.set(doc(d, 'chats', chat.id, 'messages', id), message);
  return batch.commit();
}
const direct = { id: DIRECT, members: ['alice', 'bob'], isGroup: false };
const group = { id: 'grp1', members: ['alice', 'bob', 'carol'], isGroup: true };

// ---- ChatService._system ----
const system = (actor, event, targets = []) => ({
  senderId: actor, type: 'system', text: [event, ...targets].join(':'), readBy: [],
  clientCreatedAt: Timestamp.now(), createdAt: serverTimestamp(),
});

// ---- ChatService.createGroup ----
function createGroup(creator = 'alice', members = ['alice', 'bob', 'carol']) {
  const d = db(creator);
  const now = Timestamp.now();
  const batch = writeBatch(d);
  batch.set(doc(d, 'chats', 'grp1'), {
    type: 'group', name: 'Family', description: '', createdBy: creator, members, admins: [creator],
    onlyAdminsCanSend: false, onlyAdminsEditInfo: false,
    lastMessage: '', lastMessageType: 'system', lastSenderId: creator, lastMessageAt: now,
    createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
  });
  batch.set(doc(d, 'chats', 'grp1', 'messages', 'sys0'), { ...system(creator, 'created'), clientCreatedAt: now });
  return batch.commit();
}

// ---- ChatService._groupUpdate ----
function groupUpdate(actor, update, event, targets = [], id = `sys-${Math.random().toString(36).slice(2)}`) {
  const d = db(actor);
  const batch = writeBatch(d);
  batch.update(doc(d, 'chats', 'grp1'), { ...update, updatedAt: serverTimestamp() });
  if (event) batch.set(doc(d, 'chats', 'grp1', 'messages', id), system(actor, event, targets));
  return batch.commit();
}

describe('chat_service.dart: direct chats', () => {
  test('send (first message creates the chat) and reply', async () => {
    await assertSucceeds(send('alice', direct, 'm1'));
    await assertSucceeds(send('bob', direct, 'm2', {
      replyTo: { messageId: 'm1', senderId: 'alice', text: 'hello', type: 'text' },
    }));
  });

  test('markDelivered (query + batch) and markRead with unread reset', async () => {
    await send('alice', direct, 'm1');
    await send('alice', direct, 'm2');
    const b = db('bob');
    const s = await assertSucceeds(getDocs(query(collection(b, 'chats', DIRECT, 'messages'),
      where('receiverId', '==', 'bob'), where('status', '==', 'sent'), limit(200))));
    const batch = writeBatch(b);
    s.docs.slice(0, 1).forEach((x) => batch.update(x.ref, { status: 'delivered', deliveredAt: serverTimestamp() }));
    await assertSucceeds(batch.commit());
    const read = writeBatch(b);
    read.update(doc(b, 'chats', DIRECT, 'messages', 'm2'), {
      status: 'read', readAt: serverTimestamp(), deliveredAt: serverTimestamp(),
    });
    read.set(doc(b, 'chats', DIRECT), { unread: { bob: 0 } }, { merge: true });
    await assertSucceeds(read.commit());
  });

  test('watchChats / watchMessages / search queries', async () => {
    await send('alice', direct, 'm1');
    const b = db('bob');
    await assertSucceeds(getDocs(query(collection(b, 'chats'), where('members', 'array-contains', 'bob'))));
    await assertSucceeds(getDocs(query(collection(b, 'chats', DIRECT, 'messages'), orderBy('clientCreatedAt', 'desc'), limit(40))));
    await assertSucceeds(getDocs(query(collection(b, 'chats', DIRECT, 'messages'), orderBy('clientCreatedAt', 'desc'), limit(500))));
  });

  test('typing on and off', async () => {
    await send('alice', direct, 'm1');
    await assertSucceeds(updateDoc(doc(db('bob'), 'chats', DIRECT), { 'typing.bob': serverTimestamp() }));
    await assertSucceeds(updateDoc(doc(db('bob'), 'chats', DIRECT), { 'typing.bob': deleteField() }));
  });

  test('edit, hide for me, delete for everyone', async () => {
    await send('alice', direct, 'm1');
    const ref = (u) => doc(db(u), 'chats', DIRECT, 'messages', 'm1');
    await assertSucceeds(updateDoc(ref('alice'), { text: 'edited', edited: true, editedAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(ref('bob'), { hiddenFor: arrayUnion('bob') }));
    await assertSucceeds(updateDoc(ref('alice'), {
      deleted: true, deletedAt: serverTimestamp(), text: '', attachment: deleteField(), replyTo: deleteField(),
    }));
  });
});

describe('attachment_service.dart: inline photos and voice notes (free plan)', () => {
  const sendInline = (sender, chat, id, mime, type, size = 1234) => send(sender, chat, id, {
    type, text: '',
    attachment: { blobId: id, name: `${id}.bin`, mime, size, durationMs: 3000, width: 640, height: 480 },
    extra: (batch, d) => batch.set(doc(d, 'chats', chat.id, 'blobs', id), {
      senderId: sender, data: 'aGVsbG8=', mime, size, createdAt: serverTimestamp(),
    }),
  });

  test('photo (jpeg/png/heic) and voice (Android m4a, web webm)', async () => {
    await assertSucceeds(sendInline('alice', direct, 'p1', 'image/jpeg', 'image'));
    await assertSucceeds(sendInline('bob', direct, 'p2', 'image/png', 'image'));
    await assertSucceeds(sendInline('bob', direct, 'p3', 'image/heic', 'image'));
    await assertSucceeds(sendInline('alice', direct, 'v1', 'audio/mp4', 'audio'));
    await assertSucceeds(sendInline('alice', direct, 'v2', 'audio/webm', 'audio'));
    await assertSucceeds(sendInline('alice', direct, 'v3', 'audio/mpeg', 'audio'));
  });

  test('largest inline attachment the app allows (690 KB)', async () => {
    await assertSucceeds(sendInline('alice', direct, 'big', 'image/jpeg', 'image', 690 * 1024));
  });

  test('photo as the very first message of a chat, then delete + blob delete', async () => {
    await assertSucceeds(sendInline('alice', direct, 'p1', 'image/jpeg', 'image'));
    await assertSucceeds(getDoc(doc(db('bob'), 'chats', DIRECT, 'blobs', 'p1')));
    await assertSucceeds(updateDoc(doc(db('alice'), 'chats', DIRECT, 'messages', 'p1'), {
      deleted: true, deletedAt: serverTimestamp(), text: '', attachment: deleteField(), replyTo: deleteField(),
    }));
    await assertSucceeds(deleteDoc(doc(db('alice'), 'chats', DIRECT, 'blobs', 'p1')));
  });

  test('forwarded photo into a group', async () => {
    await createGroup();
    await assertSucceeds(sendInline('bob', group, 'f1', 'image/jpeg', 'image'));
    await assertSucceeds(send('bob', group, 'f2', { text: 'fwd', forwarded: true }));
  });
});

describe('chat_service.dart: groups', () => {
  test('createGroup, member sends, markRead (readBy + unread)', async () => {
    await assertSucceeds(createGroup());
    await assertSucceeds(send('bob', group, 'g1'));
    const c = db('carol');
    const batch = writeBatch(c);
    batch.update(doc(c, 'chats', 'grp1', 'messages', 'g1'), { readBy: arrayUnion('carol') });
    batch.set(doc(c, 'chats', 'grp1'), { unread: { carol: 0 } }, { merge: true });
    await assertSucceeds(batch.commit());
  });

  test('addMembers, setAdmin, removeMember (admin) with system messages', async () => {
    await createGroup('alice', ['alice', 'bob']);
    await assertSucceeds(groupUpdate('alice', { members: arrayUnion('carol') }, 'added', ['carol']));
    await assertSucceeds(groupUpdate('alice', { admins: arrayUnion('bob') }, 'admin_added', ['bob']));
    await assertSucceeds(groupUpdate('bob', { admins: arrayRemove('bob') }, 'admin_removed', ['bob']));
    await assertSucceeds(groupUpdate('alice', { members: arrayRemove('carol'), admins: arrayRemove('carol') }, 'removed', ['carol']));
  });

  test('updateGroupInfo by admin (rename, description, photo, remove photo) and setGroupPermissions', async () => {
    await createGroup();
    await assertSucceeds(groupUpdate('alice', { name: 'Family 2', description: 'x'.repeat(200), photoBase64: 'aGVsbG8=' }, 'renamed', ['Family 2']));
    await assertSucceeds(groupUpdate('alice', { photoBase64: deleteField() }));
    await assertSucceeds(groupUpdate('alice', { onlyAdminsCanSend: true, onlyAdminsEditInfo: true }));
  });

  test('updateGroupInfo by a member when the group allows it', async () => {
    await createGroup();
    await assertSucceeds(groupUpdate('bob', { name: 'Renamed', description: 'by bob' }, 'renamed', ['Renamed']));
  });

  test('only-admins-can-send group: admin posts, member leaves with notice', async () => {
    await createGroup();
    await groupUpdate('alice', { onlyAdminsCanSend: true });
    await assertSucceeds(send('alice', group, 'a1'));
    // leaveGroup: notice first (still a member), then remove self
    await assertSucceeds(setDoc(doc(db('bob'), 'chats', 'grp1', 'messages', 'l1'), system('bob', 'left')));
    await assertSucceeds(updateDoc(doc(db('bob'), 'chats', 'grp1'), {
      members: arrayRemove('bob'), admins: arrayRemove('bob'), updatedAt: serverTimestamp(),
    }));
  });

  test('the last admin leaves: the oldest member becomes admin', async () => {
    await createGroup();
    await assertSucceeds(setDoc(doc(db('alice'), 'chats', 'grp1', 'messages', 'l1'), system('alice', 'left')));
    await assertSucceeds(updateDoc(doc(db('alice'), 'chats', 'grp1'), {
      admins: ['bob'], members: ['bob', 'carol'], updatedAt: serverTimestamp(),
    }));
  });

  test('a group created by an older app version (extra legacy field) stays editable', async () => {
    await createGroup();
    await env.withSecurityRulesDisabled((ctx) => updateDoc(doc(ctx.firestore(), 'chats', 'grp1'), { legacyField: 1 }));
    await assertSucceeds(groupUpdate('alice', { name: 'Still works' }, 'renamed', ['Still works']));
    await assertSucceeds(send('bob', group, 'g9'));
  });

  test('deleteGroup: admin deletes messages, blobs, then the chat', async () => {
    await createGroup();
    await send('bob', group, 'g1');
    const a = db('alice');
    for (const sub of ['messages', 'blobs']) {
      const page = await assertSucceeds(getDocs(query(collection(a, 'chats', 'grp1', sub), limit(300))));
      const batch = writeBatch(a);
      page.docs.forEach((x) => batch.delete(x.ref));
      await assertSucceeds(batch.commit());
    }
    await assertSucceeds(deleteDoc(doc(a, 'chats', 'grp1')));
  });
});

describe('call_service.dart', () => {
  function startCall(caller = 'alice', callee = 'bob', id = 'call1', kind = 'video') {
    const d = db(caller);
    const batch = writeBatch(d);
    batch.set(doc(d, 'calls', id), {
      callerId: caller, calleeId: callee, members: [caller, callee], type: kind, status: 'ringing',
      offer: { sdp: 'v=0\r\n'.repeat(1500), type: 'offer' }, offerVersion: 1,
      createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
    });
    batch.set(doc(d, 'users', caller, 'calls', id), {
      callId: id, peerId: callee, type: kind, direction: 'outgoing', status: 'ringing', seen: true, createdAt: serverTimestamp(),
    });
    batch.set(doc(d, 'users', callee, 'calls', id), {
      callId: id, peerId: caller, type: kind, direction: 'incoming', status: 'missed', seen: false, createdAt: serverTimestamp(),
    });
    return batch.commit();
  }
  const cand = (from) => ({ from, candidate: 'candidate:842163049 1 udp 1677729535 1.2.3.4 3478 typ srflx', sdpMid: '0', sdpMLineIndex: 0, createdAt: serverTimestamp() });

  test('start, incoming query, accept, candidates, ICE restart, hang up, history', async () => {
    await assertSucceeds(startCall());
    const b = db('bob');
    await assertSucceeds(getDocs(query(collection(b, 'calls'), where('calleeId', '==', 'bob'), where('status', '==', 'ringing'))));
    await assertSucceeds(addDoc(collection(db('alice'), 'calls', 'call1', 'candidates'), cand('alice')));
    await assertSucceeds(updateDoc(doc(b, 'calls', 'call1'), {
      answer: { sdp: 'v=0', type: 'answer' }, answerVersion: 1, status: 'accepted',
      answeredAt: serverTimestamp(), updatedAt: serverTimestamp(),
    }));
    await assertSucceeds(updateDoc(doc(b, 'users', 'bob', 'calls', 'call1'), { status: 'answered', seen: true, answeredAt: serverTimestamp() }));
    await assertSucceeds(addDoc(collection(b, 'calls', 'call1', 'candidates'), cand('bob')));
    await assertSucceeds(updateDoc(doc(db('alice'), 'users', 'alice', 'calls', 'call1'), { status: 'answered' }));
    await assertSucceeds(updateDoc(doc(db('alice'), 'calls', 'call1'), { offer: { sdp: 'v=0', type: 'offer' }, offerVersion: 2, updatedAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(doc(b, 'calls', 'call1'), { answer: { sdp: 'v=0', type: 'answer' }, answerVersion: 2, updatedAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(doc(db('alice'), 'calls', 'call1'), { status: 'ended', endedAt: serverTimestamp(), endedBy: 'alice', updatedAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(doc(db('alice'), 'users', 'alice', 'calls', 'call1'), { status: 'answered', durationSec: 42, endedAt: serverTimestamp() }));
  });

  test('reject, busy, caller cancels; history seen', async () => {
    await startCall('alice', 'bob', 'c2', 'audio');
    await assertSucceeds(updateDoc(doc(db('bob'), 'calls', 'c2'), { status: 'rejected', endedAt: serverTimestamp(), endedBy: 'bob', updatedAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(doc(db('bob'), 'users', 'bob', 'calls', 'c2'), { status: 'rejected', seen: true }));
    await startCall('alice', 'bob', 'c3', 'audio');
    await assertSucceeds(updateDoc(doc(db('bob'), 'calls', 'c3'), { status: 'busy', updatedAt: serverTimestamp() }));
    await startCall('carol', 'bob', 'c4', 'audio');
    await assertSucceeds(updateDoc(doc(db('carol'), 'calls', 'c4'), { status: 'cancelled', endedAt: serverTimestamp(), endedBy: 'carol', updatedAt: serverTimestamp() }));
    const b = db('bob');
    await assertSucceeds(getDocs(query(collection(b, 'users', 'bob', 'calls'), orderBy('createdAt', 'desc'), limit(100))));
    const batch = writeBatch(b);
    batch.update(doc(b, 'users', 'bob', 'calls', 'c4'), { seen: true });
    await assertSucceeds(batch.commit());
  });
});

describe('user_service.dart / notification_service.dart', () => {
  test('saveProfile transaction with a new username, private settings, indexes', async () => {
    const a = db('alice');
    await assertSucceeds(runTransaction(a, async (tx) => {
      const current = await tx.get(doc(a, 'users', 'alice'));
      const old = current.data()?.username;
      tx.set(doc(a, 'usernames', 'amina'), { uid: 'alice', createdAt: serverTimestamp() });
      if (old) tx.delete(doc(a, 'usernames', old));
      tx.set(doc(a, 'users', 'alice'), {
        uid: 'alice', displayName: 'Amina', displayNameLower: 'amina', username: 'amina', usernameLower: 'amina',
        about: 'hi', updatedAt: serverTimestamp(),
      }, { merge: true });
    }));
    await assertSucceeds(setDoc(doc(a, 'users', 'alice', 'private', 'account'), {
      phoneNumber: PHONE.alice, email: 'a@example.com', discoverableByPhone: true, showInDirectory: true,
      showLastSeen: false, readReceipts: true, contactSync: false,
      notifications: { messages: true, groups: true, calls: true, preview: false },
    }, { merge: true }));
    await assertSucceeds(setDoc(doc(a, 'phoneIndex', PHONE.alice), { uid: 'alice', updatedAt: serverTimestamp() }));
    await assertSucceeds(setDoc(doc(a, 'directory', 'alice'), {
      uid: 'alice', displayName: 'Amina', displayNameLower: 'amina', username: 'amina', usernameLower: 'amina', updatedAt: serverTimestamp(),
    }));
    await assertSucceeds(updateDoc(doc(a, 'users', 'alice'), { online: deleteField(), lastSeen: deleteField() }));
    await assertSucceeds(updateDoc(doc(a, 'users', 'alice'), { online: true, lastSeen: serverTimestamp() }));
  });

  test('searchDirectory (two prefix queries, limit 20) and exact lookups', async () => {
    const c = db('carol');
    const dir = collection(c, 'directory');
    await assertSucceeds(getDocs(query(dir, where('usernameLower', '>=', 'al'), where('usernameLower', '<', 'al'), limit(20))));
    await assertSucceeds(getDocs(query(dir, where('displayNameLower', '>=', 'al'), where('displayNameLower', '<', 'al'), limit(20))));
    await assertSucceeds(getDoc(doc(c, 'usernames', 'alice')));
    await assertSucceeds(getDoc(doc(c, 'phoneIndex', PHONE.alice)));
    await assertSucceeds(getDoc(doc(c, 'users', 'alice')));
  });

  test('rules version probe: old (2026-10-25) and new (2026-10-27) apps', async () => {
    await assertSucceeds(getDoc(doc(db('alice'), 'rulesVersion', '2026-10-25')));
    await assertSucceeds(getDoc(doc(db('alice'), 'rulesVersion', '2026-10-27')));
  });

  test('block, unblock, report with every reason the app offers', async () => {
    const a = db('alice');
    await assertSucceeds(setDoc(doc(a, 'users', 'alice', 'blocked', 'bob'), { uid: 'bob', createdAt: serverTimestamp() }));
    await assertSucceeds(deleteDoc(doc(a, 'users', 'alice', 'blocked', 'bob')));
    for (const reason of ['spam', 'harassment', 'inappropriate', 'impersonation', 'other']) {
      await assertSucceeds(addDoc(collection(a, 'reports'), {
        reporterId: 'alice', reportedUid: 'bob', reason, details: 'details', chatId: DIRECT, messageId: 'm1',
        createdAt: serverTimestamp(),
      }));
    }
    await assertSucceeds(addDoc(collection(a, 'reports'), { reporterId: 'alice', reportedUid: 'bob', reason: 'spam', details: '', createdAt: serverTimestamp() }));
  });

  test('push token save and removal on sign-out', async () => {
    const a = db('alice');
    await assertSucceeds(setDoc(doc(a, 'users', 'alice', 'devices', 'tok1'), { token: 'tok1', platform: 'android', updatedAt: serverTimestamp() }));
    await assertSucceeds(deleteDoc(doc(a, 'users', 'alice', 'devices', 'tok1')));
  });

  test('deleteAccount sequence', async () => {
    const a = db('alice');
    await setDoc(doc(a, 'users', 'alice', 'devices', 'tok1'), { token: 'tok1', platform: 'android', updatedAt: serverTimestamp() });
    for (const sub of ['devices', 'blocked', 'calls', 'private']) {
      const page = await assertSucceeds(getDocs(query(collection(a, 'users', 'alice', sub), limit(200))));
      const batch = writeBatch(a);
      page.docs.forEach((x) => batch.delete(x.ref));
      await assertSucceeds(batch.commit());
    }
    await assertSucceeds(deleteDoc(doc(a, 'usernames', 'alice')));
    await assertSucceeds(deleteDoc(doc(a, 'directory', 'alice')));
    await assertSucceeds(deleteDoc(doc(a, 'users', 'alice')));
  });
});
