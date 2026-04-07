const admin = require("firebase-admin");
admin.initializeApp({ storageBucket: "subliminal-words.firebasestorage.app" });
const db = admin.firestore();

async function run() {
  const snap = await db.collection("packs").doc("first-look").collection("levels")
    .where("isEnabled", "==", true)
    .get();
  
  console.log("Total enabled levels:", snap.size, "\n");
  
  for (const doc of snap.docs) {
    const d = doc.data();
    console.log("Level", doc.id, ":");
    console.log("  puzzlePath:", d.puzzlePath);
    console.log("  publicLevelPath:", d.publicLevelPath || "(NOT SET)");
    console.log("  submissionStatus:", d.submissionStatus || "(NOT SET)");
    console.log("  submissionId:", d.submissionId || "(NOT SET)");
    console.log("  creatorUid:", d.creatorUid || "(NOT SET)");
    console.log("  creatorName:", d.creatorName || "(NOT SET)");
    
    // If publicLevelPath is set, try resolving it
    if (d.publicLevelPath) {
      try {
        const resolvedDoc = await db.doc(d.publicLevelPath).get();
        if (resolvedDoc.exists) {
          const resolved = resolvedDoc.data();
          console.log("  >>> RESOLVED puzzlePath:", resolved.puzzlePath);
          console.log("  >>> SAME?", resolved.puzzlePath === d.puzzlePath);
        } else {
          console.log("  >>> RESOLVED DOC DOES NOT EXIST!");
        }
      } catch(e) {
        console.log("  >>> RESOLVE ERROR:", e.message);
      }
    }
    console.log("");
  }
}

run().then(() => process.exit(0)).catch(e => { console.error(e); process.exit(1); });
