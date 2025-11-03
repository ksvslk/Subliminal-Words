import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' hide Category;
import 'package:logging/logging.dart';
import 'package:operation_hermes/config/firebase_options.dart';
import 'package:operation_hermes/data/sw_level.dart';
import 'package:operation_hermes/data/pack.dart';
import 'package:operation_hermes/data/category.dart';

class FirebaseService {
  static final _log = Logger('FirebaseService');

  // Define the ID of the pack that has bundled levels.
  // Map of bundled pack IDs to their respective asset paths.
  static const Map<String, String> bundledPackAssets = {
    // words category
    'first-look': 'assets/data/words/first_look.json',
    'secret-forms': 'assets/data/words/secret_forms.json',
    'subtle-deceit': 'assets/data/words/subtle_deceit.json',
    'hidden-goals': 'assets/data/words/hidden_goals.json',
    // faces category
    'red-carpet': 'assets/data/faces/red_carpet.json',
    'spotlight': 'assets/data/faces/spotlight.json',
    'player-focus': 'assets/data/faces/player_focus.json',
    // characters category
    'italian-brainrot': 'assets/data/characters/italian_brainrot.json',
    // Add new bundled packs here, e.g.:
    // 'my_new_pack_id': 'assets/data/my_new_pack.json',
  };

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instanceFor(
      bucket: DefaultFirebaseOptions.currentPlatform.storageBucket!);

  FirebaseService() {
    _db.settings = const Settings(persistenceEnabled: true);
  }

  final Map<String, String> _urlCache = {};

  Future<String> getDownloadUrl(String storagePath) async {
    debugPrint(
        "[FirebaseService] Requesting URL for storagePath: '$storagePath'");

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
      debugPrint(
          "[FirebaseService] !!! FAILED to get download URL for '$storagePath'. Error: $e");
      // This is often a permissions error. Check your Firebase Storage Rules from Step 1.
      return '';
    }
  }

  // --- 💡 STREAM METHODS (for UI) ---

  /// Gets a live stream of categories.
  /// REQUIRES: 'totalLevels' (number) field on each category document.
  Stream<List<Category>> getCategoriesStream() {
    return _db
        .collection('categories')
        .where('isEnabled', isEqualTo: true)
        .orderBy('order')
        .snapshots() // This is cached and instant
        .map((categoriesSnapshot) {
      // This is synchronous

      final categories = <Category>[];
      for (final doc in categoriesSnapshot.docs) {
        final categoryData = doc.data();

        // 💡 Read totalLevels directly from the document.
        final totalLevels = categoryData['totalLevels'] as int? ?? 0;

        categories.add(
            Category.fromMap(doc.id, categoryData, totalLevels: totalLevels));
      }
      return categories;
    });
  }

  /// Gets a live stream of packs for a category.
  /// REQUIRES: 'totalLevels' (number) field on each pack document.
  Stream<List<Pack>> getPacksStream(String categoryId) {
    return _db
        .collection('packs')
        .where('categoryId', isEqualTo: categoryId)
        .where('isEnabled', isEqualTo: true)
        .orderBy('order')
        .snapshots() // This is cached and instant
        .map((snapshot) {
      // This is synchronous

      final packs = <Pack>[];
      for (final doc in snapshot.docs) {
        final packData = doc.data();
        final packId = doc.id;

        // 💡 Read totalLevels directly from the document.
        final totalLevels = packData['totalLevels'] as int? ?? 0;

        packs.add(Pack.fromMap(packId, packData, totalLevels: totalLevels));
      }
      return packs;
    });
  }

  /// Gets a live stream of levels for a pack (Hybrid Approach)
  /// This will still have a brief load as it awaits local assets.
  Stream<List<SWLevel>> getLevelsStream(String packId) {
    // 1. Load local bundled levels (this is a Future)
    final localLevelsFuture = () async {
      final Map<int, SWLevel> levelsMap = {};
      if (bundledPackAssets.containsKey(packId)) {
        try {
          final String jsonString =
              await rootBundle.loadString(bundledPackAssets[packId]!);
          final List<dynamic> jsonList = json.decode(jsonString);
          for (var levelJson in jsonList) {
            final level =
                SWLevel.fromJson(packId, levelJson as Map<String, dynamic>);
            levelsMap[level.nr] = level;
          }
          debugPrint(
              "[FirebaseService] Loaded ${levelsMap.length} bundled levels for pack '$packId'.");
        } catch (e) {
          debugPrint(
              "[FirebaseService] !!! FAILED to load bundled levels for pack '$packId'. Error: $e");
        }
      }
      return levelsMap;
    }();

    // 2. Get the live stream of remote levels
    final remoteLevelsStream = _db
        .collection('packs')
        .doc(packId)
        .collection('levels')
        .where('isEnabled', isEqualTo: true)
        .snapshots();

    // 3. Combine them
    // This asyncMap is necessary to wait for localLevelsFuture
    return remoteLevelsStream.asyncMap((remoteSnapshot) async {
      final levelsMap = await localLevelsFuture;

      for (final doc in remoteSnapshot.docs) {
        final remoteLevel = SWLevel.fromFirestore(doc.id, packId, doc.data());
        levelsMap[remoteLevel.nr] = remoteLevel;
      }

      final sortedLevels = levelsMap.values.toList();
      sortedLevels.sort((a, b) => a.nr.compareTo(b.nr));
      return sortedLevels;
    });
  }

  // --- 💡 FUTURE-BASED METHODS (for LevelModel logic) ---

  /// 💡 ADDED THIS METHOD BACK
  /// Gets level data for a specific pack (one-time fetch).
  Future<List<SWLevel>> getLevels(String packId, {bool offline = false}) async {
    final Map<int, SWLevel> levelsMap = {};

    // 1. If it's the initial pack, load bundled levels from local JSON.
    if (bundledPackAssets.containsKey(packId)) {
      try {
        final String jsonString =
            await rootBundle.loadString(bundledPackAssets[packId]!);
        final List<dynamic> jsonList = json.decode(jsonString);
        for (var levelJson in jsonList) {
          final level =
              SWLevel.fromJson(packId, levelJson as Map<String, dynamic>);
          levelsMap[level.nr] = level;
        }
        debugPrint(
            "[FirebaseService] Loaded ${levelsMap.length} bundled levels for pack '$packId'.");
      } catch (e) {
        debugPrint(
            "[FirebaseService] !!! FAILED to load bundled levels for pack '$packId'. Error: $e");
      }
    }

    // 2. Fetch levels from Firestore.
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
        debugPrint(
            "[FirebaseService] Could not fetch remote level updates for pack '$packId' (user might be offline). Proceeding with local data. Error: $e");
      }
    }

    // Convert the map of actual, enabled levels back to a sorted list.
    final sortedLevels = levelsMap.values.toList();
    sortedLevels.sort((a, b) => a.nr.compareTo(b.nr));

    return sortedLevels;
  }

  /// One-time fetch for packs in a category.
  /// Relies on denormalized `totalLevels` field.
  Future<List<Pack>> getPacks(String categoryId) async {
    final snapshot = await _db
        .collection('packs')
        .where('categoryId', isEqualTo: categoryId)
        .where('isEnabled', isEqualTo: true)
        .orderBy('order')
        .get(); // <-- One-time fetch

    final packs = <Pack>[];
    for (final doc in snapshot.docs) {
      final packData = doc.data();
      final packId = doc.id;

      // 💡 Read denormalized data, just like in the stream
      final totalLevels = packData['totalLevels'] as int? ?? 0;

      packs.add(Pack.fromMap(packId, packData, totalLevels: totalLevels));
    }
    return packs;
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

      _log.info("doc: $doc");
      _log.info("doc info: ${doc.id} : $packId");

      if (doc.exists && doc.data() != null) {
        _log.info("doc data: ${doc.data()}");
        return SWLevel.fromFirestore(doc.id, packId, doc.data()!);
      }
      return null;
    } on FirebaseException catch (e) {
      debugPrint("[FirebaseService] Failed to get level $packId/$levelNr: $e");
      rethrow;
    }
  }

  /// Get a single pack from Firestore by its ID.
  Future<Pack?> getPack(String packId) async {
    try {
      debugPrint(
          "[FirebaseService] getPack: Attempting to fetch pack with ID: $packId");
      final doc = await _db.collection('packs').doc(packId).get();

      if (doc.exists && doc.data() != null) {
        debugPrint(
            "[FirebaseService] getPack: Successfully fetched pack $packId.");

        // 💡 Read totalLevels directly from the document.
        final totalLevels = doc.data()?['totalLevels'] as int? ?? 0;

        return Pack.fromMap(doc.id, doc.data()!, totalLevels: totalLevels);
      }
      debugPrint(
          "[FirebaseService] getPack: Pack $packId does not exist or data is null.");
      return null;
    } on FirebaseException catch (e) {
      debugPrint("[FirebaseService] Failed to get pack $packId: $e");
      return null;
    }
  }


}
