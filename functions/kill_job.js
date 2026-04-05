const { initializeApp, applicationDefault } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');

initializeApp({
  credential: applicationDefault(),
  projectId: 'subliminal-words'
});
const db = getFirestore();

async function kill() {
  const levels = await db.collectionGroup('levels').get();
  let count = 0;
  for (const doc of levels.docs) {
      if (doc.data()?.editorData?.pendingPuzzleGeneration) {
          await doc.ref.update({
              'editorData.pendingPuzzleGeneration': FieldValue.delete()
          });
          count++;
          console.log(`Cleared job for level: ${doc.id}`);
      }
  }
  console.log(`Cleared ${count} stuck jobs.`);
}
kill().then(() => process.exit(0)).catch(e => { console.error(e); process.exit(1); });
