import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' hide Category;
import 'package:operation_hermes/config/firebase_options.dart';
import 'package:operation_hermes/data/sw_level.dart';
import 'package:operation_hermes/data/pack.dart';
import 'package:operation_hermes/data/category.dart';

class FirebaseService {
  // Define the ID of the pack that has bundled levels.
  // Map of bundled pack IDs to their respective asset paths.
  static const Map<String, String> bundledPackAssets = {
    // words category
    'first-look': 'assets/data/words/first_look.json',
    //'secret_forms': 'assets/data/words/secret_forms.json',
    //'subtle_deceit': 'assets/data/words/random_faces.json',
    //'hidden_goals': 'assets/data/words/hidden_goals.json',
    // faces category
    //'red_carpet': 'assets/data/faces/red_carpet.json',
    //'spotlight': 'assets/data/faces/spotlight.json',
    //'player_focus': 'assets/data/faces/player_focus.json',
    // characters category
    'italian-brainrot': 'assets/data/characters/italian_brainrot.json',
    // Add new bundled packs here, e.g.:
    // 'my_new_pack_id': 'assets/data/my_new_pack.json',
  };

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instanceFor(
      bucket: DefaultFirebaseOptions.currentPlatform.storageBucket!);

  final Map<String, String> _urlCache = {};

  Future<String> getDownloadUrl(String storagePath) async {
    debugPrint("[FirebaseService] Requesting URL for storagePath: '$storagePath'");

    if (storagePath.isEmpty) {
      debugPrint("[FirebaseService] Path is empty, returning empty URL.");
      return '';
    }
    if (_urlCache.containsKey(storagePath)) {
      debugPrint("[FirebaseService] Returning cached URL.");
      return _urlCache[storagePath]!;
    }
    try {
      // This is the correct method for relative paths like "categories/..."
      final ref = _storage.ref(storagePath);
      final url = await ref.getDownloadURL();

      debugPrint("[FirebaseService] Successfully fetched URL: '$url'");
      _urlCache[storagePath] = url;
      return url;
    } catch (e) {
      debugPrint("[FirebaseService] !!! FAILED to get download URL for '$storagePath'. Error: $e");
      // This is often a permissions error. Check your Firebase Storage Rules from Step 1.
      return '';
    }
  }

  Future<List<Category>> getCategories() async {
    final snapshot = await _db
        .collection('categories')
        .where('isEnabled', isEqualTo: true)
        .orderBy('order')
        .get();
    return snapshot.docs
        .map((doc) => Category.fromMap(doc.id, doc.data()))
        .toList();
  }

  Future<List<Pack>> getPacks(String categoryId) async {
    final snapshot = await _db
        .collection('packs')
        .where('categoryId', isEqualTo: categoryId)
        .where('isEnabled', isEqualTo: true)
        .orderBy('order')
        .get();

    final packs = <Pack>[];
    for (final doc in snapshot.docs) {
      final packData = doc.data();
      final packId = doc.id;

      // Dynamically get the true count of enabled levels for this pack.
      final levelsSnapshot = await _db
          .collection('packs')
          .doc(packId)
          .collection('levels')
          .where('isEnabled', isEqualTo: true)
          .count()
          .get();
      final totalLevels = levelsSnapshot.count ?? 0;

      packs.add(Pack.fromMap(packId, packData, totalLevels: totalLevels));
    }
    return packs;
  }

  /// Gets level data for a specific pack.
  ///
  /// This method uses a hybrid approach:
  /// 1. For the initial pack, it loads bundled levels from a local JSON asset.
  /// 2. It then fetches the corresponding levels from Firestore.
  /// 3. Firestore data overwrites local data, allowing for remote updates/hotfixes.
  /// 4. For other packs, it fetches directly from Firestore.
  Future<List<SWLevel>> getLevels(String packId, {bool offline = false}) async {
    final Map<int, SWLevel> levelsMap = {};

    // 1. If it's the initial pack, load bundled levels from local JSON.
    if (bundledPackAssets.containsKey(packId)) {
      try {
        final String jsonString =
            await rootBundle.loadString(bundledPackAssets[packId]!);
        final List<dynamic> jsonList = json.decode(jsonString);
        for (var levelJson in jsonList) {
          final level = SWLevel.fromJson(packId, levelJson as Map<String, dynamic>);
          levelsMap[level.nr] = level;
        }
        debugPrint(
            "[FirebaseService] Loaded ${levelsMap.length} bundled levels for pack '$packId'.");
      } catch (e) {
        debugPrint(
            "[FirebaseService] !!! FAILED to load bundled levels for pack '$packId'. Error: $e");
      }
    }

    // 2. Fetch levels from Firestore. This will overwrite bundled levels if they exist,
    // allowing for hotfixes. For other packs, this is the primary data source.
    // If we are starting offline, we do not want to fetch from Firestore,
    // as it might serve stale cached data with remote paths.
    if (!offline) {
      try {
        final snapshot = await _db
            .collection('packs')
            .doc(packId)
            .collection('levels')
            .where('isEnabled', isEqualTo: true)
            .get();

        for (final doc in snapshot.docs) {
          final remoteLevel = SWLevel.fromFirestore(doc.id, packId, doc.data());
          // Remote data (from Firestore) always overwrites local bundled data.
          levelsMap[remoteLevel.nr] = remoteLevel;
        }
      } on FirebaseException catch (e) {
        // This is not a critical error if we have bundled levels.
        // Log the failure but allow the app to proceed with the local data.
        debugPrint(
            "[FirebaseService] Could not fetch remote level updates for pack '$packId' (user might be offline). Proceeding with local data. Error: $e");
      }
    }

    // Convert the map of actual, enabled levels back to a sorted list.
    final sortedLevels = levelsMap.values.toList();
    sortedLevels.sort((a, b) => a.nr.compareTo(b.nr));

    return sortedLevels;
  }

  /// Get a single level from Firestore
  Future<SWLevel?> getLevel(String packId, int levelNr) async {
    try {
      final doc = await _db
          .collection('packs')
          .doc(packId)
          .collection('levels')
          .doc(levelNr.toString())
          .get();
      
      if (doc.exists && doc.data() != null) {
        return SWLevel.fromFirestore(doc.id, packId, doc.data()!);
      }
      return null;
    } on FirebaseException catch (e) {
      debugPrint("[FirebaseService] Failed to get level $packId/$levelNr: $e");
      // Re-throw the exception so the UI layer can handle it.
      rethrow;
    }
  }

  /// Get a single pack from Firestore by its ID.
  Future<Pack?> getPack(String packId) async {
    try {
      debugPrint("[FirebaseService] getPack: Attempting to fetch pack with ID: $packId");
      final doc = await _db
          .collection('packs')
          .doc(packId)
          .get();
      
      if (doc.exists && doc.data() != null) {
        debugPrint("[FirebaseService] getPack: Successfully fetched pack $packId.");
        // Also calculate the correct total levels for this single pack.
        final levelsSnapshot = await _db
            .collection('packs')
            .doc(packId)
            .collection('levels')
            .where('isEnabled', isEqualTo: true)
            .count()
            .get();
        final totalLevels = levelsSnapshot.count ?? 0;

        return Pack.fromMap(doc.id, doc.data()!, totalLevels: totalLevels);
      }
      debugPrint("[FirebaseService] getPack: Pack $packId does not exist or data is null.");
      return null;
    } on FirebaseException catch (e) {
      debugPrint("[FirebaseService] Failed to get pack $packId: $e");
      return null; // Return null on error, or rethrow if you want calling code to handle it.
    }
  }
}