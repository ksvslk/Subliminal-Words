const test = require('node:test');
const assert = require('node:assert/strict');

const {
  validateWritableCreatorDraft,
} = require('../src/creator_draft_access');

test('validateWritableCreatorDraft rejects a missing draft', () => {
  assert.throws(
    () => validateWritableCreatorDraft(null),
    /could not be found/i,
  );
});

test('validateWritableCreatorDraft rejects a locked draft', () => {
  assert.throws(
    () =>
      validateWritableCreatorDraft(
        { isLocked: true },
        { lockedMessage: 'Locked draft.' },
      ),
    /locked draft/i,
  );
});

test('validateWritableCreatorDraft accepts an unlocked draft', () => {
  assert.deepEqual(
    validateWritableCreatorDraft({ isLocked: false, name: 'Bed' }),
    { isLocked: false, name: 'Bed' },
  );
});
