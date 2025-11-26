import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:operation_hermes/config/firebase_options.dart';
import 'package:operation_hermes/data/sw_level.dart';
import 'package:operation_hermes/data/pack.dart';
import 'package:operation_hermes/data/category.dart';

class FirebaseService {
  static final _log = Logger('FirebaseService');

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
  };

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instanceFor(
      bucket: DefaultFirebaseOptions.currentPlatform.storageBucket!);

  FirebaseService() {
    _db.settings = const Settings(persistenceEnabled: true);
  }

  final Map<String, String> _urlCache = {};

  Future<String> getDownloadUrl(String storagePath) async {
    if (storagePath.isEmpty) {
      return '';
    }
    if (_urlCache.containsKey(storagePath)) {
      return _urlCache[storagePath]!;
    }
    try {
      final ref = _storage.ref(storagePath);
      final url = await ref.getDownloadURL();
      _urlCache[storagePath] = url;
      return url;
    } catch (e) {
      return '';
    }
  }

  Stream<List<Category>> getCategoriesStream() {
    return _db
        .collection('categories')
        .where('isEnabled', isEqualTo: true)
        .orderBy('order')
        .snapshots()
        .map((categoriesSnapshot) {
      final categories = <Category>[];
      for (final doc in categoriesSnapshot.docs) {
        final categoryData = doc.data();
        final totalLevels = categoryData['totalLevels'] as int? ?? 0;
        categories.add(
            Category.fromMap(doc.id, categoryData, totalLevels: totalLevels));
      }
      return categories;
    });
  }

  Stream<List<Pack>> getPacksStream(String categoryId) {
    return _db
        .collection('packs')
        .where('categoryId', isEqualTo: categoryId)
        .where('isEnabled', isEqualTo: true)
        .orderBy('order')
        .snapshots()
        .map((snapshot) {
      final packs = <Pack>[];
      for (final doc in snapshot.docs) {
        final packData = doc.data();
        final packId = doc.id;
        final totalLevels = packData['totalLevels'] as int? ?? 0;
        packs.add(Pack.fromMap(packId, packData, totalLevels: totalLevels));
      }
      return packs;
    });
  }

  Stream<List<SWLevel>> getLevelsStream(String packId) {
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
        } catch (e) {
          _log.warning(
              "[FirebaseService] !!! FAILED to load bundled levels for pack '$packId'. Error: $e");
        }
      }
      return levelsMap;
    }();

    final remoteLevelsStream = _db
        .collection('packs')
        .doc(packId)
        .collection('levels')
        .where('isEnabled', isEqualTo: true)
        .snapshots();

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

  Future<List<SWLevel>> getLevels(String packId) async {
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
      } catch (e) {
        _log.warning(
            "[FirebaseService] !!! FAILED to load bundled levels for pack '$packId'. Error: $e");
      }
    }

    try {
      final snapshot = await _db
          .collection('packs')
          .doc(packId)
          .collection('levels')
          .where('isEnabled', isEqualTo: true)
          .get();

      for (final doc in snapshot.docs) {
        final remoteLevel = SWLevel.fromFirestore(doc.id, packId, doc.data());
        levelsMap[remoteLevel.nr] = remoteLevel;
      }
    } on FirebaseException catch (e) {
      _log.warning(
          "[FirebaseService] Could not fetch remote level updates for pack '$packId' (user might be offline). Proceeding with local data. Error: $e");
    }

    final sortedLevels = levelsMap.values.toList();
    sortedLevels.sort((a, b) => a.nr.compareTo(b.nr));
    return sortedLevels;
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
      final totalLevels = packData['totalLevels'] as int? ?? 0;
      packs.add(Pack.fromMap(packId, packData, totalLevels: totalLevels));
    }
    return packs;
  }

  Future<SWLevel?> getLevel(String packId, int levelNr) async {
    int maxRetries = 3;
    Duration delay = const Duration(seconds: 1);
    int attempt = 0;

    while (attempt < maxRetries) {
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
        _log.warning("[FirebaseService] Level doc not found: $packId/$levelNr");
        return SWLevel(
          id: "",
          nr: -1,
          packId: packId,
          name: "",
          hintType: "",
          hints: {},
          puzzlePath: "",
          puzzleThumbnailPath: "",
          solutionPath: "",
          tooltipStart: "",
          tooltipEnd: "",
          isEnabled: true,
          createdAt: DateTime.now(),
          modifiedAt: DateTime.now()
        );
      } on FirebaseException catch (e) {
        if (e.code == 'unavailable' && attempt < maxRetries - 1) {
          _log.warning(
              "[FirebaseService] Firebase unavailable, attempt ${attempt + 1}. Retrying in $delay...",
              e);
          await Future.delayed(delay);
          delay = delay * 2;
          attempt++;
        } else {
          _log.warning(
              "[FirebaseService] Failed to get level $packId/$levelNr: $e");
          rethrow;
        }
      } catch (e, st) {
        _log.severe(
            "[FirebaseService] Unexpected error in getLevel: $packId/$levelNr",
            e,
            st);
        rethrow;
      }
    }
    return null;
  }

  Future<Pack?> getPack(String packId) async {
    try {
      final doc = await _db.collection('packs').doc(packId).get();
      if (doc.exists && doc.data() != null) {
        final totalLevels = doc.data()?['totalLevels'] as int? ?? 0;
        return Pack.fromMap(doc.id, doc.data()!, totalLevels: totalLevels);
      }
      _log.warning(
          "[FirebaseService] getPack: Pack $packId does not exist or data is null.");
      return null;
    } on FirebaseException catch (e) {
      _log.warning("[FirebaseService] Failed to get pack $packId: $e");
      return null;
    }
  }
}
