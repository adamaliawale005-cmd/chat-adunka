// Firestore security rules tests. Run in CI with:
//   firebase emulators:exec --project demo-aduchat --only firestore,storage "node --test"
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, test } from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  arrayUnion,
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
  writeBatch,
} from 'firebase/firestore';

let env;
const PHONE = { alice: '+252610000001', bob: '+252610000002', carol: '+966500000003' };

function db(uid) {
  return env.authenticatedContext(uid, { phone_number: PHONE[uid] }).firestore();
}
const anon = () => env.unauthenticatedContext().firestore();

function profile(uid, extra = {}) {
  return {
    uid,
    displayName: uid[0].toUpperCase() + uid.slice(1),
    displayNameLower: uid,
    about: '',
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    ...extra,
  };
}

function directMessage(sender, receiver, text = 'hello') {
  return {
    senderId: sender,
    receiverId: receiver,
    type: 'text',
    text,
    status: 'sent',
    clientCreatedAt: new Date(),
    createdAt: serverTimestamp(),
  };
}

async function sendDirect(sender, receiver, id, text = 'hello') {
  const d = db(sender);
  const chatId = [sender, receiver].sort().join('_');
  const batch = writeBatch(d);
  batch.set(doc(d, 'chats', chatId), {
    type: 'direct',
    members: [sender, receiver].sort(),
    lastMessage: text,
    lastMessageType: 'text',
    lastSenderId: sender,
    lastMessageAt: new Date(),
    updatedAt: serverTimestamp(),
  }, { merge: true });
  batch.set(doc(d, 'chats', chatId, 'messages', id), directMessage(sender, receiver, text));
  return batch.commit();
}

async function seedGroup(extra = {}) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'chats', 'group1'), {
      type: 'group',
      name: 'Family',
      createdBy: 'alice',
      members: ['alice', 'bob'],
      admins: ['alice'],
      updatedAt: new Date(),
      ...extra,
    });
  });
}

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-aduchat',
    firestore: { rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8') },
  });
});

beforeEach(async () => {
  await env.clearFirestore();
});

after(async () => {
  await env.cleanup();
});

describe('user profiles', () => {
  test('a user can create their own profile', async () => {
    await assertSucceeds(setDoc(doc(db('alice'), 'users', 'alice'), profile('alice')));
  });

  test('a user cannot create a profile for someone else', async () => {
    await assertFails(setDoc(doc(db('alice'), 'users', 'bob'), profile('bob')));
  });

  test('phone numbers cannot be stored in the public profile', async () => {
    await assertFails(setDoc(doc(db('alice'), 'users', 'alice'),
      profile('alice', { phoneNumber: PHONE.alice })));
  });

  test('profiles can be read one at a time but not listed', async () => {
    await setDoc(doc(db('alice'), 'users', 'alice'), profile('alice'));
    await assertSucceeds(getDoc(doc(db('bob'), 'users', 'alice')));
    await assertFails(getDocs(collection(db('bob'), 'users')));
    await assertFails(getDoc(doc(anon(), 'users', 'alice')));
  });

  test('private account data is only readable by its owner', async () => {
    await assertSucceeds(setDoc(doc(db('alice'), 'users', 'alice', 'private', 'account'),
      { phoneNumber: PHONE.alice }));
    await assertFails(getDoc(doc(db('bob'), 'users', 'alice', 'private', 'account')));
  });
});

describe('usernames', () => {
  test('a free username can be claimed and used in the profile', async () => {
    const d = db('alice');
    const batch = writeBatch(d);
    batch.set(doc(d, 'usernames', 'alice_1'), { uid: 'alice', createdAt: serverTimestamp() });
    batch.set(doc(d, 'users', 'alice'), profile('alice', { username: 'alice_1', usernameLower: 'alice_1' }));
    await assertSucceeds(batch.commit());
  });

  test('a taken username cannot be claimed again', async () => {
    await setDoc(doc(db('alice'), 'usernames', 'samedi'), { uid: 'alice' });
    await assertFails(setDoc(doc(db('bob'), 'usernames', 'samedi'), { uid: 'bob' }));
  });

  test('the profile cannot use a username owned by someone else', async () => {
    await setDoc(doc(db('alice'), 'usernames', 'samedi'), { uid: 'alice' });
    await assertFails(setDoc(doc(db('bob'), 'users', 'bob'),
      profile('bob', { username: 'samedi', usernameLower: 'samedi' })));
  });

  test('the owner can re-claim their own username', async () => {
    await setDoc(doc(db('alice'), 'usernames', 'samedi'), { uid: 'alice' });
    await assertSucceeds(setDoc(doc(db('alice'), 'usernames', 'samedi'), { uid: 'alice' }));
  });

  test('a profile can be saved again with the same username', async () => {
    const d = db('alice');
    const batch = writeBatch(d);
    batch.set(doc(d, 'usernames', 'amina'), { uid: 'alice', createdAt: serverTimestamp() });
    batch.set(doc(d, 'users', 'alice'), profile('alice', { username: 'amina', usernameLower: 'amina' }));
    await batch.commit();
    await assertSucceeds(updateDoc(doc(d, 'users', 'alice'), { about: 'hello', online: true, lastSeen: serverTimestamp() }));
  });

  test('invalid usernames are rejected', async () => {
    await assertFails(setDoc(doc(db('alice'), 'usernames', 'A!'), { uid: 'alice' }));
  });
});

describe('phone index', () => {
  test('a user can only register their own verified phone number', async () => {
    await assertSucceeds(setDoc(doc(db('alice'), 'phoneIndex', PHONE.alice), { uid: 'alice' }));
    await assertFails(setDoc(doc(db('alice'), 'phoneIndex', PHONE.bob), { uid: 'alice' }));
  });

  test('the owner can save their phone entry again', async () => {
    await setDoc(doc(db('alice'), 'phoneIndex', PHONE.alice), { uid: 'alice' });
    await assertSucceeds(setDoc(doc(db('alice'), 'phoneIndex', PHONE.alice), { uid: 'alice' }));
  });

  test('numbers can be looked up exactly but never listed', async () => {
    await setDoc(doc(db('alice'), 'phoneIndex', PHONE.alice), { uid: 'alice' });
    await assertSucceeds(getDoc(doc(db('bob'), 'phoneIndex', PHONE.alice)));
    await assertFails(getDocs(collection(db('bob'), 'phoneIndex')));
  });
});

describe('direct messages', () => {
  test('a user can start a chat and send a message', async () => {
    await assertSucceeds(sendDirect('alice', 'bob', 'm1'));
  });

  test('outsiders cannot read or write the chat', async () => {
    await sendDirect('alice', 'bob', 'm1');
    await assertFails(getDoc(doc(db('carol'), 'chats', 'alice_bob')));
    await assertFails(getDocs(collection(db('carol'), 'chats', 'alice_bob', 'messages')));
    await assertFails(setDoc(doc(db('carol'), 'chats', 'alice_bob', 'messages', 'x'),
      directMessage('carol', 'bob')));
  });

  test('a user cannot send a message as someone else', async () => {
    await assertFails(setDoc(doc(db('alice'), 'chats', 'alice_bob', 'messages', 'x'),
      directMessage('bob', 'alice')));
  });

  test('members can list their chats', async () => {
    await sendDirect('alice', 'bob', 'm1');
    await assertSucceeds(getDocs(query(collection(db('bob'), 'chats'),
      where('members', 'array-contains', 'bob'))));
  });

  test('only the receiver can mark a message delivered or read', async () => {
    await sendDirect('alice', 'bob', 'm1');
    const path = ['chats', 'alice_bob', 'messages', 'm1'];
    await assertFails(updateDoc(doc(db('alice'), ...path), { status: 'read' }));
    await assertSucceeds(updateDoc(doc(db('bob'), ...path), { status: 'delivered', deliveredAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(doc(db('bob'), ...path), { status: 'read', readAt: serverTimestamp() }));
  });

  test('the receiver cannot change the message text', async () => {
    await sendDirect('alice', 'bob', 'm1');
    await assertFails(updateDoc(doc(db('bob'), 'chats', 'alice_bob', 'messages', 'm1'), { text: 'changed' }));
  });

  test('the sender can edit and delete their own message', async () => {
    await sendDirect('alice', 'bob', 'm1');
    const ref = doc(db('alice'), 'chats', 'alice_bob', 'messages', 'm1');
    await assertSucceeds(updateDoc(ref, { text: 'edited', edited: true, editedAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(ref, { deleted: true, deletedAt: serverTimestamp(), text: '' }));
  });

  test('anyone in the chat can hide a message for themselves only', async () => {
    await sendDirect('alice', 'bob', 'm1');
    const ref = (u) => doc(db(u), 'chats', 'alice_bob', 'messages', 'm1');
    await assertSucceeds(updateDoc(ref('bob'), { hiddenFor: arrayUnion('bob') }));
    await assertFails(updateDoc(ref('bob'), { hiddenFor: ['bob', 'alice'] }));
  });

  test('typing indicators can only be set for yourself', async () => {
    await sendDirect('alice', 'bob', 'm1');
    const ref = doc(db('bob'), 'chats', 'alice_bob');
    await assertSucceeds(updateDoc(ref, { 'typing.bob': new Date() }));
    await assertFails(updateDoc(ref, { 'typing.alice': new Date() }));
  });

  test('a blocked user cannot send messages', async () => {
    await setDoc(doc(db('bob'), 'users', 'bob', 'blocked', 'alice'), { uid: 'alice', createdAt: serverTimestamp() });
    await assertFails(sendDirect('alice', 'bob', 'm2'));
  });

  test('inline attachments are private to the chat', async () => {
    await sendDirect('alice', 'bob', 'm1');
    const blob = { senderId: 'alice', data: 'aGVsbG8=', mime: 'image/jpeg', size: 5, createdAt: serverTimestamp() };
    await assertSucceeds(setDoc(doc(db('alice'), 'chats', 'alice_bob', 'blobs', 'b1'), blob));
    await assertSucceeds(getDoc(doc(db('bob'), 'chats', 'alice_bob', 'blobs', 'b1')));
    await assertFails(getDoc(doc(db('carol'), 'chats', 'alice_bob', 'blobs', 'b1')));
  });
});

describe('group chats', () => {
  test('a user can create a group they administer', async () => {
    await assertSucceeds(setDoc(doc(db('alice'), 'chats', 'groupNew'), {
      type: 'group', name: 'Friends', createdBy: 'alice',
      members: ['alice', 'bob'], admins: ['alice'], updatedAt: serverTimestamp(),
    }));
  });

  test('non-members cannot read the group or its messages', async () => {
    await seedGroup();
    await assertFails(getDoc(doc(db('carol'), 'chats', 'group1')));
    await assertFails(getDocs(collection(db('carol'), 'chats', 'group1', 'messages')));
  });

  test('members can send messages', async () => {
    await seedGroup();
    await assertSucceeds(setDoc(doc(db('bob'), 'chats', 'group1', 'messages', 'g1'), {
      senderId: 'bob', type: 'text', text: 'hi all', readBy: [],
      clientCreatedAt: new Date(), createdAt: serverTimestamp(),
    }));
  });

  test('only admins can add members', async () => {
    await seedGroup();
    await assertFails(updateDoc(doc(db('bob'), 'chats', 'group1'), { members: ['alice', 'bob', 'carol'] }));
    await assertSucceeds(updateDoc(doc(db('alice'), 'chats', 'group1'), { members: ['alice', 'bob', 'carol'] }));
  });

  test('a member can leave the group', async () => {
    await seedGroup();
    await assertSucceeds(updateDoc(doc(db('bob'), 'chats', 'group1'), {
      members: ['alice'], admins: ['alice'], updatedAt: serverTimestamp(),
    }));
  });

  test('when only admins can send, other members cannot', async () => {
    await seedGroup({ onlyAdminsCanSend: true });
    await assertFails(setDoc(doc(db('bob'), 'chats', 'group1', 'messages', 'g2'), {
      senderId: 'bob', type: 'text', text: 'hi', readBy: [],
      clientCreatedAt: new Date(), createdAt: serverTimestamp(),
    }));
  });

  test('only admins can delete the group', async () => {
    await seedGroup();
    await assertFails(deleteDoc(doc(db('bob'), 'chats', 'group1')));
    await assertSucceeds(deleteDoc(doc(db('alice'), 'chats', 'group1')));
  });
});

describe('calls', () => {
  const newCall = () => ({
    callerId: 'alice', calleeId: 'bob', members: ['alice', 'bob'], type: 'video',
    status: 'ringing', offer: { sdp: 'x', type: 'offer' }, offerVersion: 1,
    createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
  });

  test('a user can call another user', async () => {
    await assertSucceeds(setDoc(doc(db('alice'), 'calls', 'c1'), newCall()));
  });

  test('outsiders cannot read the call', async () => {
    await setDoc(doc(db('alice'), 'calls', 'c1'), newCall());
    await assertFails(getDoc(doc(db('carol'), 'calls', 'c1')));
  });

  test('the callee can find incoming calls and answer', async () => {
    await setDoc(doc(db('alice'), 'calls', 'c1'), newCall());
    await assertSucceeds(getDocs(query(collection(db('bob'), 'calls'),
      where('calleeId', '==', 'bob'), where('status', '==', 'ringing'))));
    await assertSucceeds(updateDoc(doc(db('bob'), 'calls', 'c1'), {
      answer: { sdp: 'y', type: 'answer' }, status: 'accepted', answeredAt: serverTimestamp(),
    }));
  });

  test('the caller cannot write the answer', async () => {
    await setDoc(doc(db('alice'), 'calls', 'c1'), newCall());
    await assertFails(updateDoc(doc(db('alice'), 'calls', 'c1'), { answer: { sdp: 'z', type: 'answer' } }));
  });

  test('a blocked user cannot call', async () => {
    await setDoc(doc(db('bob'), 'users', 'bob', 'blocked', 'alice'), { uid: 'alice', createdAt: serverTimestamp() });
    await assertFails(setDoc(doc(db('alice'), 'calls', 'c2'), newCall()));
  });

  test('ICE candidates are private to the call', async () => {
    await setDoc(doc(db('alice'), 'calls', 'c1'), newCall());
    const cand = { from: 'alice', candidate: 'candidate:1', sdpMid: '0', sdpMLineIndex: 0, createdAt: serverTimestamp() };
    await assertSucceeds(setDoc(doc(db('alice'), 'calls', 'c1', 'candidates', 'k1'), cand));
    await assertFails(getDocs(collection(db('carol'), 'calls', 'c1', 'candidates')));
  });

  test('the caller can record a missed call in the callee history', async () => {
    const d = db('alice');
    const batch = writeBatch(d);
    batch.set(doc(d, 'calls', 'c3'), newCall());
    batch.set(doc(d, 'users', 'bob', 'calls', 'c3'), {
      callId: 'c3', peerId: 'alice', type: 'video', direction: 'incoming', status: 'missed',
      createdAt: serverTimestamp(),
    });
    await assertSucceeds(batch.commit());
    await assertFails(getDocs(collection(db('alice'), 'users', 'bob', 'calls')));
  });
});

describe('reports', () => {
  test('users can report but not read reports', async () => {
    await assertSucceeds(setDoc(doc(db('alice'), 'reports', 'r1'), {
      reporterId: 'alice', reportedUid: 'bob', reason: 'spam', details: '', createdAt: serverTimestamp(),
    }));
    await assertFails(getDoc(doc(db('alice'), 'reports', 'r1')));
  });
});
