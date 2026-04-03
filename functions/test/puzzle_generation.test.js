const test = require('node:test');
const assert = require('node:assert/strict');

const {
  normalizePendingPuzzleGeneration,
  validatePuzzleGenerationDraftForStart,
  validatePuzzleGenerationDraftForStatus,
} = require('../src/puzzle_generation');

test('normalizePendingPuzzleGeneration returns null for missing or blank data', () => {
  assert.equal(normalizePendingPuzzleGeneration(null), null);
  assert.equal(
    normalizePendingPuzzleGeneration({
      editorData: {
        pendingPuzzleGeneration: {
          status: 'running',
          jobId: '   ',
        },
      },
    }),
    null,
  );
});

test('normalizePendingPuzzleGeneration extracts normalized pending job info', () => {
  assert.deepEqual(
    normalizePendingPuzzleGeneration({
      editorData: {
        pendingPuzzleGeneration: {
          status: 'RUNNING',
          jobId: ' job-123 ',
        },
      },
    }),
    {
      status: 'running',
      jobId: 'job-123',
    },
  );
});

test('validatePuzzleGenerationDraftForStart rejects missing or locked levels', () => {
  assert.throws(
    () => validatePuzzleGenerationDraftForStart(null),
    /could not be found/i,
  );
  assert.throws(
    () => validatePuzzleGenerationDraftForStart({ isLocked: true }),
    /cannot generate a new puzzle/i,
  );
});

test('validatePuzzleGenerationDraftForStatus requires matching pending job', () => {
  assert.throws(
    () =>
      validatePuzzleGenerationDraftForStatus(
        {
          isLocked: false,
          editorData: {},
        },
        'job-1',
      ),
    /no longer has a pending puzzle generation/i,
  );

  assert.throws(
    () =>
      validatePuzzleGenerationDraftForStatus(
        {
          isLocked: false,
          editorData: {
            pendingPuzzleGeneration: {
              status: 'running',
              jobId: 'job-2',
            },
          },
        },
        'job-1',
      ),
    /no longer matches the selected draft/i,
  );
});

test('validatePuzzleGenerationDraftForStatus accepts a matching pending job', () => {
  assert.deepEqual(
    validatePuzzleGenerationDraftForStatus(
      {
        isLocked: false,
        editorData: {
          pendingPuzzleGeneration: {
            status: 'running',
            jobId: 'job-7',
          },
        },
      },
      'job-7',
    ),
    {
      status: 'running',
      jobId: 'job-7',
    },
  );
});
