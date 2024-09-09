import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:logging/logging.dart';
import 'package:operation_hermes/game/model/competition_data.dart';

class CompetitionController {
  static final Logger _log = Logger('CompetitionController');

  static const competitionGoalLevel = 60;

  static const finishedFieldName = 'finished';
  static const currentLevelFieldName = 'current_level';
  static const promoCodeFieldName = 'promo_code';
  static const playersCollectionName = 'players';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<CompetitionData?> updatePlayerLevel(int newLevel) async {
    try {
      final pid = FirebaseAuth.instance.currentUser?.uid;
      if (newLevel == competitionGoalLevel) {
        await _firestore.runTransaction((transaction) async {
          DocumentSnapshot snapshot = await transaction
              .get(_firestore.collection(playersCollectionName).doc(pid));

          if (snapshot.exists) {
            bool finished = snapshot.get(finishedFieldName);
            if (!finished) {
              transaction.update(
                  _firestore.collection(playersCollectionName).doc(pid), {
                currentLevelFieldName: newLevel,
                finishedFieldName: true,
              });
            }
          }
        });

        await waitForPromoCodeAssignment(pid);

        DocumentSnapshot updatedSnapshot =
            await _firestore.collection(playersCollectionName).doc(pid).get();

        if (updatedSnapshot.exists) {
          String promoCode = updatedSnapshot.get(promoCodeFieldName);
          bool finished = updatedSnapshot.get(finishedFieldName);
          return CompetitionData(true, finished, promoCode);
        }
      }
      return null;
    } catch (e) {
      _log.info('Error updating player level: $e');
      return null;
    }
  }

  Future<void> waitForPromoCodeAssignment(String? playerId) async {
    var playerDoc = FirebaseFirestore.instance.collection(playersCollectionName).doc(playerId);

    // Use a stream to listen for changes in the 'promoCodeAssigned' field
    await playerDoc.snapshots().firstWhere((doc) {
      // Check if the Cloud Function has completed its task
      return doc.data()?[promoCodeFieldName] != "";
    });

    // Once the promoCodeAssigned is true, proceed to fetch the updated data
    var updatedData = await playerDoc.get();
    _log.info("Promo code assignment complete: ${updatedData.data()}");
  }

  Future<bool> joinCompetition(int currentLevel) async {
    try {
      final pid = FirebaseAuth.instance.currentUser?.uid;
      DocumentSnapshot userDoc =
          await _firestore.collection(playersCollectionName).doc(pid).get();

      if (!userDoc.exists) {
        await _firestore.collection(playersCollectionName).doc(pid).set({
          currentLevelFieldName: currentLevel,
        });
        _log.info("Successfully joined competition.");
        return Future.value(true);
      } else {
        _log.info("Did not enroll.");
        return Future.value(false);
      }
    } catch (error) {
      _log.severe("Error joining competition or writing document: $error");
      return Future.value(false);
    }
  }

  Future<CompetitionData?> getCompetitionData() async {
    try {
      final pid = FirebaseAuth.instance.currentUser?.uid;
      _log.info("UID: $pid");
      final docRef = _firestore.collection(playersCollectionName).doc(pid);

      // Await the document snapshot
      DocumentSnapshot doc = await docRef.get();

      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        String promoCode = data[promoCodeFieldName] ?? "";
        bool finished = data[finishedFieldName] ?? false;
        bool enrolled = true;

        // Return the competition data
        return CompetitionData(enrolled, finished, promoCode);
      } else {
        // Return default data if the document doesn't exist
        return CompetitionData(false, false, "");
      }
    } catch (e) {
      _log.severe("Error getting document: $e");
      return null; // Return null in case of an error
    }
  }
}
