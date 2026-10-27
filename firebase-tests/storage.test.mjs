// Cloud Storage security rules tests (run in the emulator by CI).
import { readFileSync } from 'node:fs';
import { after, before, describe, test } from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { doc, setDoc } from 'firebase/firestore';
import { deleteObject, getBytes, ref, uploadBytes } from 'firebase/storage';

let env;
const bytes = new Uint8Array([1, 2, 3, 4]);
const image = { contentType: 'image/jpeg' };

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-aduchat',
    firestore: { rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8') },
    storage: { rules: readFileSync(new URL('../storage.rules', import.meta.url), 'utf8') },
  });
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'chats', 'group1'), {
      type: 'group', name: 'Family', createdBy: 'alice', members: ['alice', 'bob'], admins: ['alice'],
    });
    // carol has blocked alice
    await setDoc(doc(ctx.firestore(), 'users', 'carol', 'blocked', 'alice'), { uid: 'alice' });
  });
});

after(async () => {
  await env.cleanup();
});

const storage = (uid) => env.authenticatedContext(uid).storage();

describe('chat attachments', () => {
  test('a member can upload into their own folder of a direct chat', async () => {
    await assertSucceeds(uploadBytes(ref(storage('alice'), 'chats/alice_bob/alice/a.jpg'), bytes, image));
  });

  test('a member cannot upload into someone else\'s folder', async () => {
    await assertFails(uploadBytes(ref(storage('alice'), 'chats/alice_bob/bob/a.jpg'), bytes, image));
  });

  test('the other member can download, outsiders cannot', async () => {
    await uploadBytes(ref(storage('alice'), 'chats/alice_bob/alice/b.jpg'), bytes, image);
    await assertSucceeds(getBytes(ref(storage('bob'), 'chats/alice_bob/alice/b.jpg')));
    await assertFails(getBytes(ref(storage('carol'), 'chats/alice_bob/alice/b.jpg')));
  });

  test('group membership is checked against Firestore', async () => {
    await assertSucceeds(uploadBytes(ref(storage('bob'), 'chats/group1/bob/c.jpg'), bytes, image));
    await assertFails(uploadBytes(ref(storage('carol'), 'chats/group1/carol/c.jpg'), bytes, image));
  });

  test('executables and unknown types are rejected', async () => {
    await assertFails(uploadBytes(ref(storage('alice'), 'chats/alice_bob/alice/x.bin'), bytes,
      { contentType: 'font/ttf' }));
  });

  test('installers, scripts, HTML, SVG and unknown binaries are refused', async () => {
    const up = (name, contentType) =>
      uploadBytes(ref(storage('alice'), `chats/alice_bob/alice/${name}`), bytes, { contentType });
    await assertFails(up('app.apk', 'application/vnd.android.package-archive'));
    await assertFails(up('setup.exe', 'application/x-msdownload'));
    await assertFails(up('page.html', 'text/html'));
    await assertFails(up('pic.svg', 'image/svg+xml'));
    await assertFails(up('blob.bin', 'application/octet-stream'));
    // a disguised installer (allowed type, dangerous extension)
    await assertFails(up('photo.apk', 'image/jpeg'));
    await assertSucceeds(up('report.pdf', 'application/pdf'));
    await assertSucceeds(up('voice.m4a', 'audio/mp4'));
  });

  test('size limits per type are enforced', async () => {
    const big = new Uint8Array(16 * 1024 * 1024);
    await assertFails(uploadBytes(ref(storage('alice'), 'chats/alice_bob/alice/huge.jpg'), big, image));
  });

  test('uploads are refused while the other person has blocked the sender', async () => {
    await assertFails(uploadBytes(ref(storage('alice'), 'chats/alice_carol/alice/a.jpg'), bytes, image));
  });

  test('malformed chat ids give no access', async () => {
    await assertFails(uploadBytes(ref(storage('alice'), 'chats/bob_alice/alice/a.jpg'), bytes, image));
    await assertFails(uploadBytes(ref(storage('alice'), 'chats/alice_/alice/a.jpg'), bytes, image));
  });

  test('only the sender can delete; files cannot be overwritten', async () => {
    await uploadBytes(ref(storage('alice'), 'chats/alice_bob/alice/keep.jpg'), bytes, image);
    await assertFails(deleteObject(ref(storage('bob'), 'chats/alice_bob/alice/keep.jpg')));
    await assertFails(uploadBytes(ref(storage('alice'), 'chats/alice_bob/alice/keep.jpg'), bytes, image));
  });

  test('other paths are closed', async () => {
    await assertFails(uploadBytes(ref(storage('alice'), 'anything/else.jpg'), bytes, image));
  });
});
