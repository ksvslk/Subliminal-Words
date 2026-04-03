function normalizePendingPuzzleGeneration(levelData) {
  const rawPending = levelData?.editorData?.pendingPuzzleGeneration;
  if (!rawPending || typeof rawPending !== 'object') {
    return null;
  }

  const pending = {
    jobId: String(rawPending.jobId || '').trim(),
    status: String(rawPending.status || '').trim().toLowerCase(),
  };

  if (!pending.jobId) {
    return null;
  }

  return pending;
}

function validatePuzzleGenerationDraftForStart(levelData) {
  if (!levelData) {
    throw new Error('The selected level could not be found.');
  }

  if (levelData.isLocked === true) {
    throw new Error(
      'Submitted levels are locked and cannot generate a new puzzle.',
    );
  }
}

function validatePuzzleGenerationDraftForStatus(levelData, requestedJobId) {
  validatePuzzleGenerationDraftForStart(levelData);

  const normalizedJobId = String(requestedJobId || '').trim();
  if (!normalizedJobId) {
    throw new Error('A job id is required.');
  }

  const pending = normalizePendingPuzzleGeneration(levelData);
  if (!pending) {
    throw new Error(
      'The selected draft no longer has a pending puzzle generation.',
    );
  }

  if (pending.jobId !== normalizedJobId) {
    throw new Error(
      'This puzzle generation no longer matches the selected draft.',
    );
  }

  return pending;
}

module.exports = {
  normalizePendingPuzzleGeneration,
  validatePuzzleGenerationDraftForStart,
  validatePuzzleGenerationDraftForStatus,
};
