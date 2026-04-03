const test = require('node:test');
const assert = require('node:assert/strict');

const {
  containsBlockedTerm,
  hasReviewReadyPuzzleImage,
  normalizeContentCategory,
  validateUserLevelSubmission,
} = require('../src/user_level_submission');

test('containsBlockedTerm catches profanity substrings', () => {
  assert.equal(containsBlockedTerm('clean text'), false);
  assert.equal(containsBlockedTerm('this is shit'), true);
});

test('hasReviewReadyPuzzleImage follows object-vs-other rules', () => {
  assert.equal(
    hasReviewReadyPuzzleImage({
      editorMode: 'draw_object',
      puzzlePath: 'puzzle.webp',
      solutionPath: 'solution.webp',
    }),
    true,
  );
  assert.equal(
    hasReviewReadyPuzzleImage({
      editorMode: 'draw_object',
      puzzlePath: 'same.webp',
      solutionPath: 'same.webp',
    }),
    false,
  );
  assert.equal(
    hasReviewReadyPuzzleImage({
      editorMode: 'photo_sketch',
      puzzlePath: 'puzzle.webp',
    }),
    true,
  );
});

test('normalizeContentCategory derives default categories from editor mode', () => {
  assert.equal(normalizeContentCategory('', 'highlight'), 'words');
  assert.equal(normalizeContentCategory('', 'photo_sketch'), 'faces');
  assert.equal(normalizeContentCategory('', 'draw_object'), 'objects');
  assert.equal(normalizeContentCategory('characters', 'photo_sketch'), 'characters');
});

test('validateUserLevelSubmission accepts a valid highlight level', () => {
  const result = validateUserLevelSubmission({
    creatorName: 'tere',
    name: 'AB',
    editorMode: 'highlight',
    puzzlePath: 'puzzle.webp',
    solutionPath: 'solution.svg',
    editorData: {
      hasPuzzleImage: true,
      wordLetters: [
        {
          letter: 'A',
          x: 0.25,
          y: 0.4,
          fontSize: 160,
          rotationDegrees: 0,
          scaleX: 1,
          scaleY: 1,
          skewXDegrees: 0,
          skewYDegrees: 0,
          opacity: 1,
          fontWeightValue: 400,
        },
        {
          letter: 'B',
          x: 0.65,
          y: 0.6,
          fontSize: 160,
          rotationDegrees: 0,
          scaleX: 1,
          scaleY: 1,
          skewXDegrees: 0,
          skewYDegrees: 0,
          opacity: 1,
          fontWeightValue: 700,
        },
      ],
    },
  });

  assert.equal(result.creatorName, 'tere');
  assert.equal(result.answer, 'AB');
  assert.equal(result.editorMode, 'highlight');
  assert.equal(result.contentCategory, 'words');
});

test('validateUserLevelSubmission rejects face drafts without a sanitized source image', () => {
  assert.throws(
    () =>
      validateUserLevelSubmission({
        creatorName: 'tere',
        name: 'Face',
        editorMode: 'photo_sketch',
        puzzlePath: 'puzzle.webp',
        solutionPath: 'solution.webp',
        hints: { fact: 'some fact' },
        editorData: {
          hasPuzzleImage: true,
          sourceImageSafetyStatus: 'pending',
          sourceImagePath: '',
        },
      }),
    /safety-checked before review/i,
  );
});

test('validateUserLevelSubmission rejects missing fact hints for non-word levels', () => {
  assert.throws(
    () =>
      validateUserLevelSubmission({
        creatorName: 'tere',
        name: 'Bed',
        editorMode: 'draw_object',
        puzzlePath: 'puzzle.webp',
        solutionPath: 'solution.webp',
        editorData: { hasPuzzleImage: true },
      }),
    /missing a fact hint/i,
  );
});

test('validateUserLevelSubmission rejects profanity and missing puzzle state', () => {
  assert.throws(
    () =>
      validateUserLevelSubmission({
        creatorName: 'tere',
        name: 'shit bed',
        editorMode: 'draw_object',
        puzzlePath: 'puzzle.webp',
        solutionPath: 'solution.webp',
        hints: { fact: 'a safe fact' },
        editorData: { hasPuzzleImage: true },
      }),
    /remove profanity/i,
  );

  assert.throws(
    () =>
      validateUserLevelSubmission({
        creatorName: 'tere',
        name: 'Bed',
        editorMode: 'draw_object',
        puzzlePath: '',
        solutionPath: 'solution.webp',
        hints: { fact: 'a safe fact' },
      }),
    /actual puzzle image/i,
  );
});

test('validateUserLevelSubmission rejects drafts with pending puzzle generation', () => {
  assert.throws(
    () =>
      validateUserLevelSubmission({
        creatorName: 'tere',
        name: 'Bed',
        editorMode: 'draw_object',
        puzzlePath: 'puzzle.webp',
        solutionPath: 'solution.webp',
        hints: { fact: 'a safe fact' },
        editorData: {
          hasPuzzleImage: true,
          pendingPuzzleGeneration: {
            status: 'running',
            jobId: 'job-123',
          },
        },
      }),
    /wait for puzzle generation to finish/i,
  );
});
