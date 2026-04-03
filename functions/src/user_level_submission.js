const { buildCanonicalWordSolutionSvg } = require('./word_level_svg');

const BLOCKED_TERMS = [
  'fuck',
  'shit',
  'bitch',
  'asshole',
  'cunt',
  'nigger',
  'fag',
  'porn',
  'sex',
];

function containsBlockedTerm(value) {
  const normalized = String(value || '').trim().toLowerCase();
  if (!normalized) {
    return false;
  }

  return BLOCKED_TERMS.some((term) => normalized.includes(term));
}

function hasReviewReadyPuzzleImage(levelData) {
  const editorData = levelData?.editorData || {};
  if (typeof editorData.hasPuzzleImage === 'boolean') {
    return editorData.hasPuzzleImage;
  }

  const puzzlePath = String(levelData?.puzzlePath || '').trim();
  const solutionPath = String(levelData?.solutionPath || '').trim();
  const editorMode = String(levelData?.editorMode || 'draw_object').trim();

  if (!puzzlePath) {
    return false;
  }

  if (editorMode === 'draw_object') {
    return !!solutionPath && puzzlePath !== solutionPath;
  }

  return true;
}

function normalizeContentCategory(value, editorMode) {
  const normalized = String(value || '').trim().toLowerCase();
  if (['words', 'faces', 'characters', 'objects'].includes(normalized)) {
    return normalized;
  }

  if (editorMode === 'highlight') {
    return 'words';
  }

  if (editorMode === 'photo_sketch' || editorMode === 'photoSketch') {
    return 'faces';
  }

  return 'objects';
}

function validateUserLevelSubmission(
  levelData,
  { buildWordSolutionSvg = buildCanonicalWordSolutionSvg } = {},
) {
  const creatorName = String(levelData?.creatorName || '').trim();
  const answer = String(levelData?.name || '').trim();
  const editorMode = String(levelData?.editorMode || 'draw_object').trim();
  const contentCategory = normalizeContentCategory(
    levelData?.contentCategory,
    editorMode,
  );
  const editorData = levelData?.editorData || {};
  const factText = String(levelData?.hints?.fact || '').trim();
  const tooltipStart = String(levelData?.tooltipStart || '').trim();
  const tooltipEnd = String(levelData?.tooltipEnd || '').trim();
  const sourceImageSafetyStatus = String(
    levelData?.sourceImageSafetyStatus ||
      levelData?.editorData?.sourceImageSafetyStatus ||
      '',
  )
    .trim()
    .toLowerCase();
  const sourceImagePath = String(
    levelData?.editorData?.sourceImagePath || '',
  ).trim();
  const pendingPuzzleGeneration = levelData?.editorData?.pendingPuzzleGeneration;
  const pendingPuzzleJobId = String(
    pendingPuzzleGeneration?.jobId || '',
  ).trim();

  if (!creatorName || answer.length < 2) {
    throw new Error('The level is missing a creator name or answer.');
  }

  if (editorMode !== 'highlight' && !factText) {
    throw new Error('The level is missing a fact hint.');
  }

  if (editorMode === 'highlight') {
    buildWordSolutionSvg(editorData.wordLetters, { answer });
  }

  if (
    (editorMode === 'photoSketch' || editorMode === 'photo_sketch') &&
    (sourceImageSafetyStatus !== 'clean' || !sourceImagePath)
  ) {
    throw new Error(
      'Save this face level again so the face photo can be safety-checked before review.',
    );
  }

  if (!hasReviewReadyPuzzleImage(levelData)) {
    throw new Error('Add the actual puzzle image before submitting this level.');
  }

  if (pendingPuzzleJobId) {
    throw new Error(
      'Wait for puzzle generation to finish before submitting this level.',
    );
  }

  const profanityCheckedValues = [
    creatorName,
    answer,
    tooltipStart,
    tooltipEnd,
  ];
  if (editorMode !== 'highlight') {
    profanityCheckedValues.push(factText);
  }

  for (const value of profanityCheckedValues) {
    if (containsBlockedTerm(value)) {
      throw new Error('Please remove profanity before submitting this level.');
    }
  }

  return {
    creatorName,
    answer,
    editorMode,
    contentCategory,
    editorData,
    factText,
    tooltipStart,
    tooltipEnd,
  };
}

module.exports = {
  containsBlockedTerm,
  hasReviewReadyPuzzleImage,
  normalizeContentCategory,
  validateUserLevelSubmission,
};
