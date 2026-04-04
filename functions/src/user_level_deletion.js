function normalizeSubmissionStatus(value) {
  return String(value || '').trim().toLowerCase();
}

function hasPublishedPublicLevel(levelData, submissionDocs = []) {
  const levelPublicPath = String(levelData?.publicLevelPath || '').trim();
  if (levelPublicPath) {
    return true;
  }

  if (normalizeSubmissionStatus(levelData?.submissionStatus) === 'approved') {
    return true;
  }

  return submissionDocs.some((submissionDoc) => {
    const submissionData = submissionDoc?.data || {};
    return (
      normalizeSubmissionStatus(submissionData.status) === 'approved' ||
      String(submissionData.publicLevelPath || '').trim().length > 0
    );
  });
}

function planUserLevelDeletion({ levelData, submissionDocs = [] }) {
  const published = hasPublishedPublicLevel(levelData, submissionDocs);

  return {
    published,
    deleteSubmissionDocs: !published,
    submissionDocIdsToDelete: !published
      ? submissionDocs.map((submissionDoc) => submissionDoc.id)
      : [],
  };
}

module.exports = {
  hasPublishedPublicLevel,
  planUserLevelDeletion,
};
