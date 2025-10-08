import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:logging/logging.dart';
import 'package:operation_hermes/change_notifier/competition_data.dart';

class CompetitionController {
  static final Logger _log = Logger('CompetitionController');

  static const competitionGoalLevel = 60;

  static var playersCollectionName = Platform.isAndroid ? 'players' : 'players_ios';
  static const finishedFieldName = 'finished';

  static var promoCodeCollectionName = Platform.isAndroid ? 'promo_code' : 'promo_code_ios';
  static const assignedFieldName = 'assigned';
  static const assignedToFieldName = 'assigned_to';

  static const codeFieldName = 'code';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<CompetitionData?> updatePlayerLevel(int newLevel) async {
    try {
      // Check if the player reached the competition goal level
      if (newLevel != competitionGoalLevel) return null;

      final pid = FirebaseAuth.instance.currentUser?.uid;
      if (pid == null) return null; // Return if user is not authenticated

      return await _firestore.runTransaction((transaction) async {
        final playerRef = _firestore.collection(playersCollectionName).doc(pid);
        final playerSnapshot = await transaction.get(playerRef);

        // Proceed only if player document exists and hasn't finished
        if (playerSnapshot.exists &&
            !(playerSnapshot.get(finishedFieldName) ?? false)) {

          // Fetch an available promo code
          final promoCode = await _fetchAvailablePromoCode();

          if (promoCode == null) {
            transaction.update(playerRef, {
              finishedFieldName: true,
              codeFieldName: "OUT OF STOCK",
            });
            return CompetitionData(true, true, "OUT OF STOCK");
          }

          // Update player with promo code and mark as finished
          transaction.update(playerRef, {
            finishedFieldName: true,
            codeFieldName: promoCode,
          });

          return CompetitionData(true, true, promoCode);
        }
        return null;
      });
    } catch (e) {
      _log.severe('Error updating player level: $e');
      return null;
    }
  }

  Future<String?> _fetchAvailablePromoCode() async {
    // Query for an unused promo code
    final promoSnapshot = await _firestore
        .collection(promoCodeCollectionName)
        .where(assignedFieldName, isEqualTo: false)
        .limit(1)
        .get();

    if (promoSnapshot.docs.isNotEmpty) {
      final promoCodeDoc = promoSnapshot.docs.first;
      final promoCode = promoCodeDoc.data()[codeFieldName] as String;

      // Mark the promo code as assigned
      await promoCodeDoc.reference.update({
        assignedFieldName: true,
        assignedToFieldName: FirebaseAuth.instance.currentUser?.uid,
      });

      return promoCode;
    }
    return null; // No promo codes available
  }

  Future<bool> joinCompetition(int currentLevel) async {
    try {
      final pid = FirebaseAuth.instance.currentUser?.uid;

      DocumentSnapshot userDoc =
          await _firestore.collection(playersCollectionName).doc(pid).get();

      if (!userDoc.exists) {
        await _firestore
            .collection(playersCollectionName)
            .doc(pid)
            .set({finishedFieldName: false, codeFieldName: ""});

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
      if (pid == null) {
        return null; // Return null if the user is not authenticated
      }

      final docRef = _firestore.collection(playersCollectionName).doc(pid);

      // Await the document snapshot
      final snapshot = await docRef.get();

      if (snapshot.exists) {
        final data = snapshot.data();

        // Check if data is not null
        if (data != null) {
          String promoCode = data[codeFieldName] ?? "";
          bool finished = data[finishedFieldName] ?? false;
          bool enrolled = true;

          // Return the competition data
          return CompetitionData(enrolled, finished, promoCode);
        }
      }

      // Return default data if the document doesn't exist or is null
      return CompetitionData(false, false, "");
    } catch (e) {
      _log.severe("Error getting document: $e");
      return null; // Return null in case of an error
    }
  }
}
