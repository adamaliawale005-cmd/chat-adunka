// Unit tests for TURN credential generation (run by CI: node --test functions/).
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { test } = require('node:test');
const { turnCredentialsFor } = require('./turn');

const SECRET = 'test-shared-secret-0123456789';

test('credentials follow the TURN REST API format and expire', () => {
  const c = turnCredentialsFor('uidA', SECRET, 1_000_000, 3600);
  assert.equal(c.username, '1003600:uidA');
  const expected = crypto.createHmac('sha1', SECRET).update('1003600:uidA').digest('base64');
  assert.equal(c.credential, expected);
});

test('different users and times get different credentials', () => {
  const a = turnCredentialsFor('uidA', SECRET, 1_000_000, 3600);
  const b = turnCredentialsFor('uidB', SECRET, 1_000_000, 3600);
  const a2 = turnCredentialsFor('uidA', SECRET, 1_000_001, 3600);
  assert.notEqual(a.credential, b.credential);
  assert.notEqual(a.credential, a2.credential);
});

test('weak secrets, long lifetimes and malformed user ids are refused', () => {
  assert.throws(() => turnCredentialsFor('uidA', 'short', 0, 3600));
  assert.throws(() => turnCredentialsFor('uidA', SECRET, 0, 7 * 24 * 3600));
  assert.throws(() => turnCredentialsFor('a:b', SECRET, 0, 3600));
  assert.throws(() => turnCredentialsFor('', SECRET, 0, 3600));
});
