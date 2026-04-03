function validateWritableCreatorDraft(
  levelData,
  {
    missingMessage = 'The selected level could not be found.',
    lockedMessage = 'Submitted levels are locked and cannot be changed.',
  } = {},
) {
  if (!levelData) {
    throw new Error(missingMessage);
  }

  if (levelData.isLocked === true) {
    throw new Error(lockedMessage);
  }

  return levelData;
}

module.exports = {
  validateWritableCreatorDraft,
};
