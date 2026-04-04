const test = require('node:test');
const assert = require('node:assert/strict');

const {
  hasPublishedPublicLevel,
  planUserLevelDeletion,
} = require('../src/user_level_deletion');

test('hasPublishedPublicLevel is false for draft-only levels', () => {
  assert.equal(
    hasPublishedPublicLevel(
      {
        submissionStatus: 'draft',
        publicLevelPath: '',
      },
      [
        {
          id: 'submission-1',
          data: { status: 'rejected', publicLevelPath: '' },
        },
      ],
    ),
    false,
  );
});

test('hasPublishedPublicLevel is true when owner level is approved', () => {
  assert.equal(
    hasPublishedPublicLevel({
      submissionStatus: 'approved',
      publicLevelPath: '',
    }),
    true,
  );
});

test('hasPublishedPublicLevel is true when an approved submission is already live', () => {
  assert.equal(
    hasPublishedPublicLevel(
      {
        submissionStatus: 'pending_review',
        publicLevelPath: '',
      },
      [
        {
          id: 'submission-1',
          data: {
            status: 'approved',
            publicLevelPath: 'packs/faces-community/levels/abc123',
          },
        },
      ],
    ),
    true,
  );
});

test('planUserLevelDeletion removes admin submissions for non-live drafts', () => {
  assert.deepEqual(
    planUserLevelDeletion({
      levelData: {
        submissionStatus: 'pending_review',
        publicLevelPath: '',
      },
      submissionDocs: [
        { id: 'submission-1', data: { status: 'pending_review' } },
        { id: 'submission-2', data: { status: 'rejected' } },
      ],
    }),
    {
      published: false,
      deleteSubmissionDocs: true,
      submissionDocIdsToDelete: ['submission-1', 'submission-2'],
    },
  );
});

test('planUserLevelDeletion preserves admin history for published levels', () => {
  assert.deepEqual(
    planUserLevelDeletion({
      levelData: {
        submissionStatus: 'approved',
        publicLevelPath: 'packs/words-community/levels/live-1',
      },
      submissionDocs: [
        {
          id: 'submission-1',
          data: {
            status: 'approved',
            publicLevelPath: 'packs/words-community/levels/live-1',
          },
        },
        {
          id: 'submission-2',
          data: { status: 'rejected', publicLevelPath: '' },
        },
      ],
    }),
    {
      published: true,
      deleteSubmissionDocs: false,
      submissionDocIdsToDelete: [],
    },
  );
});
