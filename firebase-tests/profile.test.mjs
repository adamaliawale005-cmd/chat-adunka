// Regression tests for profile creation (the "permission-denied when saving
// my profile" report). The helper below performs exactly the same Firestore
// operations, in the same order, as UserService.saveProfile in the app.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { after, describe, test } from 'node:test';

import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import {
  doc,
  getDoc,
  runTransaction,
  serverTimestamp,
  setDoc,
  updateDoc,
} from 'firebase/firestore';

/** Reads a document bypassing the rules (test setup only). */
async function adminGet(env, ...path) {
  let snap;
  await env.withSecurityRulesDisabled(async (c) => {
    snap = await getDoc(doc(c.firestore(), ...path));
  });
  return snap;
}

const rules = (file) => readFileSync(new URL(file, import.meta.url), 'utf8');

/** Same steps as lib/services/user_service.dart saveProfile(). */
async function saveProfile(db, auth, { name, username, about = '', photo }) {
  const uid = auth.uid;
  const step = async (label, fn) => {
    try {
      return await fn();
    } catch (e) {
      e.step = label;
      throw e;
    }
  };

  // 1. read private settings (errors are ignored by the app)
  try {
    await getDoc(doc(db, 'users', uid, 'private', 'account'));
  } catch (_) { /* app falls back to defaults */ }

  // 2. transaction: read profile + username claim, write both
  await step('transaction users/{uid} + usernames/{username}', () =>
    runTransaction(db, async (tx) => {
      const userRef = doc(db, 'users', uid);
      const current = await tx.get(userRef);
      const old = current.exists() ? current.data().username : undefined;
      if (username !== old) {
        const claimRef = doc(db, 'usernames', username);
        const claim = await tx.get(claimRef);
        if (claim.exists() && claim.data().uid !== uid) throw new Error('taken');
        tx.set(claimRef, { uid, createdAt: serverTimestamp() });
        if (old) tx.delete(doc(db, 'usernames', old));
      }
      const data = {
        uid,
        displayName: name,
        displayNameLower: name.toLowerCase(),
        username,
        usernameLower: username,
        about,
        updatedAt: serverTimestamp(),
      };
      if (!current.exists()) data.createdAt = serverTimestamp();
      if (photo) data.photoBase64 = photo;
      tx.set(userRef, data, { merge: true });
    }));

  // 3. private account record
  const priv = {
    discoverableByPhone: true,
    showInDirectory: true,
    showLastSeen: true,
    readReceipts: true,
    contactSync: false,
    notifications: { messages: true, groups: true, calls: true, preview: true },
  };
  if (auth.phone) priv.phoneNumber = auth.phone;
  if (auth.email) priv.email = auth.email;
  await step('users/{uid}/private/account', () =>
    setDoc(doc(db, 'users', uid, 'private', 'account'), priv, { merge: true }));

  // 4. opt-in indexes
  if (auth.phone) {
    await step('phoneIndex/{phone}', () =>
      setDoc(doc(db, 'phoneIndex', auth.phone), { uid, updatedAt: serverTimestamp() }));
  }
  await step('directory/{uid}', () =>
    setDoc(doc(db, 'directory', uid), {
      uid,
      displayName: name,
      displayNameLower: name.toLowerCase(),
      username,
      usernameLower: username,
      updatedAt: serverTimestamp(),
    }));
}

const emailUser = { uid: 'emailUser1', email: 'amina@example.com', token: { email: 'amina@example.com', email_verified: false } };
const phoneUser = { uid: 'phoneUser1', phone: '+252610000009', token: { phone_number: '+252610000009' } };
const ctx = (env, u) => env.authenticatedContext(u.uid, u.token).firestore();

describe('profile creation with the current firestore.rules', () => {
  let env;
  test('setup', async () => {
    env = await initializeTestEnvironment({
      projectId: 'demo-aduchat',
      firestore: { rules: rules('../firestore.rules') },
    });
    await env.clearFirestore();
  });

  test('a new email account can create its profile', async () => {
    await saveProfile(ctx(env, emailUser), emailUser, { name: 'Amina', username: 'amina' });
    const snap = await adminGet(env, 'users', emailUser.uid);
    assert.equal(snap.data().username, 'amina');
    assert.equal(snap.data().phoneNumber, undefined, 'no phone number in the public profile');
    assert.equal((await adminGet(env, 'usernames', 'amina')).data().uid, emailUser.uid);
    assert.equal((await adminGet(env, 'users', emailUser.uid, 'private', 'account')).data().email, emailUser.email);
    assert.equal((await adminGet(env, 'directory', emailUser.uid)).exists(), true);
  });

  test('a new phone account can create its profile', async () => {
    await saveProfile(ctx(env, phoneUser), phoneUser, { name: 'Yusuf Ali', username: 'yusuf' });
  });

  test('saving the profile again (same username) works', async () => {
    await saveProfile(ctx(env, emailUser), emailUser, { name: 'Amina A.', username: 'amina', about: 'hi' });
  });

  test('changing the username releases the old one', async () => {
    await saveProfile(ctx(env, emailUser), emailUser, { name: 'Amina', username: 'amina_2' });
    assert.equal((await adminGet(env, 'usernames', 'amina')).exists(), false);
    assert.equal((await adminGet(env, 'usernames', 'amina_2')).data().uid, emailUser.uid);
  });

  test('a profile photo can be saved', async () => {
    await saveProfile(ctx(env, phoneUser), phoneUser, { name: 'Yusuf', username: 'yusuf', photo: 'aGVsbG8=' });
  });

  test('presence updates after the profile exists work', async () => {
    await updateDoc(doc(ctx(env, emailUser), 'users', emailUser.uid), {
      online: true, lastSeen: serverTimestamp(),
    });
  });

  test('someone else cannot take a claimed username', async () => {
    const other = { uid: 'otherUser1', email: 'x@example.com', token: { email: 'x@example.com' } };
    await assert.rejects(
      saveProfile(ctx(env, other), other, { name: 'X', username: 'amina_2' }),
      /taken|permission/i,
    );
  });

  test('a user cannot create a profile for another uid', async () => {
    const d = ctx(env, emailUser);
    await assert.rejects(setDoc(doc(d, 'users', 'someoneElse'), {
      uid: 'someoneElse', displayName: 'Fake', displayNameLower: 'fake',
    }), /permission/i);
  });

  test('signed-out users cannot create profiles', async () => {
    const d = env.unauthenticatedContext().firestore();
    await assert.rejects(setDoc(doc(d, 'users', 'nobody'), {
      uid: 'nobody', displayName: 'N', displayNameLower: 'n',
    }), /permission/i);
  });

  test('the rules version probe answers for the current version only', async () => {
    const d = ctx(env, emailUser);
    await getDoc(doc(d, 'rulesVersion', '2026-10-27'));
    await assert.rejects(getDoc(doc(d, 'rulesVersion', 'old')), /permission/i);
  });

  test('cleanup', async () => {
    await env.cleanup();
  });
});

// Diagnosis: the same flow against rules that may still be published in the
// Firebase console. These document which document write is refused.
describe('diagnosis with outdated rules', () => {
  test('Phase 2 rules refuse the users/{uid} write in the transaction', async () => {
    const env = await initializeTestEnvironment({
      projectId: 'demo-aduchat',
      firestore: { rules: rules('./fixtures/phase2.rules') },
    });
    const err = await saveProfile(ctx(env, emailUser), emailUser, { name: 'Amina', username: 'amina' })
      .then(() => null, (e) => e);
    await env.cleanup();
    assert.ok(err, 'expected a permission error');
    assert.match(String(err.code || err.message), /permission/i);
    assert.equal(err.step, 'transaction users/{uid} + usernames/{username}');
  });

  test('default "production mode" rules refuse the first read in the transaction', async () => {
    const env = await initializeTestEnvironment({
      projectId: 'demo-aduchat',
      firestore: { rules: rules('./fixtures/locked.rules') },
    });
    const err = await saveProfile(ctx(env, emailUser), emailUser, { name: 'Amina', username: 'amina' })
      .then(() => null, (e) => e);
    await env.cleanup();
    assert.ok(err, 'expected a permission error');
    assert.equal(err.step, 'transaction users/{uid} + usernames/{username}');
  });
});

after(() => {});
