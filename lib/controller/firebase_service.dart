import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:logging/logging.dart';
import 'package:operation_hermes/config/firebase_options.dart';
import 'package:operation_hermes/data/sw_level.dart';
import 'package:operation_hermes/data/pack.dart';
import 'package:operation_hermes/data/category.dart';
import 'package:operation_hermes/data/user_level_metadata.dart';
import 'package:operation_hermes/editor/generation_image_budget.dart';

class _SanitizedUserUpload {
  final String storagePath;
  final String contentType;
  final int width;
  final int height;
  final int sizeBytes;
  final String safetyStatus;
  final String nsfwCheckStatus;

  const _SanitizedUserUpload({
    required this.storagePath,
    required this.contentType,
    required this.width,
    required this.height,
    required this.sizeBytes,
    required this.safetyStatus,
    required this.nsfwCheckStatus,
  });

  factory _SanitizedUserUpload.fromMap(Map<String, dynamic> data) {
    return _SanitizedUserUpload(
      storagePath: (data['storagePath'] as String? ?? '').trim(),
      contentType: (data['contentType'] as String? ?? '').trim(),
      width: (data['width'] as num?)?.round() ?? 0,
      height: (data['height'] as num?)?.round() ?? 0,
      sizeBytes: (data['sizeBytes'] as num?)?.round() ?? 0,
      safetyStatus: (data['safetyStatus'] as String? ?? '').trim(),
      nsfwCheckStatus: (data['nsfwCheckStatus'] as String? ?? '').trim(),
    );
  }
}

class PendingPuzzleGenerationException implements Exception {
  final String jobId;
  final String message;

  const PendingPuzzleGenerationException({
    required this.jobId,
    required this.message,
  });

  @override
  String toString() => message;
}

class FirebaseService {
  static final _log = Logger('FirebaseService');
  static const String _runpodProxyBaseUrl =
      'https://runpod-proxy-549374376791.us-central1.run.app';
  static const String _creatorModerationCollection = 'creatorModeration';

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
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  FirebaseService() {
    _db.settings = const Settings(persistenceEnabled: true);
  }

  final Map<String, String> _urlCache = {};

  String? get currentUserId => FirebaseAuth.instance.currentUser?.uid;

  Future<Map<String, dynamic>> _getCreatorModerationData() async {
    final uid = currentUserId;
    if (uid == null || uid.isEmpty) {
      return const <String, dynamic>{};
    }

    try {
      final snapshot =
          await _db.collection(_creatorModerationCollection).doc(uid).get();
      if (!snapshot.exists || snapshot.data() == null) {
        return const <String, dynamic>{};
      }
      return Map<String, dynamic>.from(snapshot.data()!);
    } catch (_) {
      return const <String, dynamic>{};
    }
  }

  String _creatorBlockedMessage(Map<String, dynamic> moderationData) {
    final reason = '${moderationData['reason'] ?? ''}'.trim();
    if (reason.isNotEmpty) {
      return 'Level creation is unavailable for this account right now. $reason';
    }
    return 'Level creation is unavailable for this account right now.';
  }

  Future<void> assertUserCanCreateLevels() async {
    final moderationData = await _getCreatorModerationData();
    if (moderationData['userLevelCreationBlocked'] == true) {
      throw StateError(_creatorBlockedMessage(moderationData));
    }
  }

  CollectionReference<Map<String, dynamic>> _userLevelsCollection(String uid) {
    return _db.collection('userLevels').doc(uid).collection('levels');
  }

  Future<void> savePushToken(String token) async {
    final uid = currentUserId;
    final normalizedToken = token.trim();
    if (uid == null || uid.isEmpty || normalizedToken.isEmpty) {
      return;
    }

    String? collectionName;
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        collectionName = 'fcmTokensIos';
        break;
      case TargetPlatform.android:
        collectionName = 'fcmTokensAndroid';
        break;
      default:
        collectionName = null;
    }

    if (collectionName == null) {
      return;
    }

    await _db.collection(collectionName).doc(uid).set(
      <String, dynamic>{
        'token': normalizedToken,
        'updatedAt': FieldValue.serverTimestamp(),
        'platform': defaultTargetPlatform.name,
      },
      SetOptions(merge: true),
    );
  }

  Future<void> _deleteStoragePathIfExists(String storagePath) async {
    if (storagePath.isEmpty) {
      return;
    }

    try {
      await _storage.ref(storagePath).delete();
      _urlCache.remove(storagePath);
    } catch (_) {
      // Missing or already-removed draft assets should not block cleanup.
    }
  }

  Future<Uint8List?> getStorageBytes(
    String storagePath, {
    int maxSizeBytes = 8 * 1024 * 1024,
  }) async {
    if (storagePath.isEmpty) {
      return null;
    }

    try {
      return await _storage.ref(storagePath).getData(maxSizeBytes);
    } catch (_) {
      return null;
    }
  }

  Future<_SanitizedUserUpload> _sanitizeAndStoreUserUpload({
    required String levelId,
    required String uploadKind,
    required Uint8List imageBytes,
  }) async {
    await assertUserCanCreateLevels();
    try {
      final callable = _functions.httpsCallable('sanitizeUserLevelUpload');
      final response = await callable.call<Map<String, dynamic>>(
        <String, dynamic>{
          'levelId': levelId,
          'uploadKind': uploadKind,
          'imageBase64': base64Encode(imageBytes),
        },
      );
      return _SanitizedUserUpload.fromMap(Map<String, dynamic>.from(
        response.data,
      ));
    } on FirebaseFunctionsException catch (error) {
      final parts = <String>[
        error.code.trim(),
        (error.message ?? '').trim(),
        if (error.details != null)
          error.details is String
              ? (error.details as String).trim()
              : jsonEncode(error.details),
      ].where((part) => part.isNotEmpty).toList();

      throw StateError(
        parts.isEmpty ? error.toString() : parts.join(' | '),
      );
    }
  }

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
            documentId: "",
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
            modifiedAt: DateTime.now());
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

  Stream<List<SWLevel>> getMyLevelsStream() {
    return Stream<List<SWLevel>>.multi((controller) {
      StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? levelsSub;

      void bindUser(User? user) {
        levelsSub?.cancel();
        final uid = user?.uid;
        if (uid == null || uid.isEmpty) {
          controller.add(const <SWLevel>[]);
          return;
        }

        levelsSub = _userLevelsCollection(uid).snapshots().listen((snapshot) {
          final levels = snapshot.docs
              .map(
                (doc) => SWLevel.fromFirestore(doc.id, 'my-levels', doc.data()),
              )
              .toList();

          levels.sort((a, b) {
            final modifiedCompare = b.modifiedAt.compareTo(a.modifiedAt);
            if (modifiedCompare != 0) {
              return modifiedCompare;
            }
            return b.nr.compareTo(a.nr);
          });

          _log.info('Loaded ${levels.length} creator-owned levels for uid=$uid');
          controller.add(levels);
        }, onError: controller.addError);
      }

      bindUser(FirebaseAuth.instance.currentUser);
      final authSub =
          FirebaseAuth.instance.authStateChanges().listen(bindUser, onError: controller.addError);

      controller.onCancel = () async {
        await levelsSub?.cancel();
        await authSub.cancel();
      };
    });
  }

  Future<SWLevel?> getMyLevelByNumber(int nr) async {
    final uid = currentUserId;
    if (uid == null || uid.isEmpty) {
      return null;
    }

    final snapshot = await _userLevelsCollection(uid)
        .where('nr', isEqualTo: nr)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) {
      return null;
    }

    final doc = snapshot.docs.first;
    return SWLevel.fromFirestore(doc.id, 'my-levels', doc.data());
  }

  Future<SWLevel?> getMyLevel(String levelId) async {
    final uid = currentUserId;
    if (uid == null || uid.isEmpty) {
      return null;
    }

    final doc = await _userLevelsCollection(uid).doc(levelId).get();
    if (!doc.exists || doc.data() == null) {
      return null;
    }

    return SWLevel.fromFirestore(doc.id, 'my-levels', doc.data()!);
  }

  bool _hasStoredReviewReadyPuzzleImage(Map<String, dynamic> levelData) {
    final editorData =
        Map<String, dynamic>.from(levelData['editorData'] ?? const {});
    final storedFlag = editorData['hasPuzzleImage'];
    if (storedFlag is bool) {
      return storedFlag;
    }

    final puzzlePath = levelData['puzzlePath'] as String? ?? '';
    final solutionPath = levelData['solutionPath'] as String? ?? '';
    final editorMode =
        levelData['editorMode'] as String? ?? UserLevelEditorMode.drawObject;

    if (puzzlePath.isEmpty) {
      return false;
    }

    if (editorMode == UserLevelEditorMode.drawObject) {
      return solutionPath.isNotEmpty && puzzlePath != solutionPath;
    }

    return true;
  }

  Future<({Uint8List imageBytes, Uint8List thumbnailBytes})>
      _buildPuzzleStorageAssets(Uint8List bytes) async {
    final decodedImage = img.decodeImage(bytes);
    if (decodedImage == null) {
      throw StateError('Could not read the selected puzzle image.');
    }

    final normalizedImage =
        decodedImage.width > kStoredPuzzleDimension ||
                decodedImage.height > kStoredPuzzleDimension
            ? img.copyResize(
                decodedImage,
                width: decodedImage.width >= decodedImage.height
                    ? kStoredPuzzleDimension
                    : null,
                height: decodedImage.height > decodedImage.width
                    ? kStoredPuzzleDimension
                    : null,
                interpolation: img.Interpolation.average,
              )
            : decodedImage;

    final normalizedBytes = Uint8List.fromList(
      img.encodeJpg(normalizedImage, quality: 94),
    );

    return buildStoredPuzzleWebpAssets(normalizedBytes);
  }

  Future<String> saveDrawObjectLevel({
    String? levelId,
    required String creatorName,
    required String answer,
    required String factText,
    required String contentCategory,
    required Uint8List solutionPngBytes,
    Uint8List? puzzleImageBytes,
    bool allowReuseExistingPuzzle = true,
    required Map<String, dynamic> editorData,
  }) async {
    await assertUserCanCreateLevels();
    final uid = currentUserId;
    if (uid == null || uid.isEmpty) {
      throw StateError('You need to be signed in before saving a level.');
    }

    final levelsRef = _userLevelsCollection(uid);
    final docRef = levelId == null ? levelsRef.doc() : levelsRef.doc(levelId);

    int levelNr = 1;
    DateTime? existingCreatedAt;
    String existingPuzzlePath = '';
    String existingPuzzleThumbnailPath = '';
    bool canReuseExistingPuzzle = false;

    if (levelId != null) {
      final existingDoc = await docRef.get();
      if (existingDoc.exists && existingDoc.data() != null) {
        final existingData = existingDoc.data()!;
        if (existingData['isLocked'] == true) {
          throw StateError(
              'Submitted levels are locked. Duplicate the level to change it.');
        }
        levelNr = existingData['nr'] ?? 1;
        existingCreatedAt = (existingData['createdAt'] as Timestamp?)?.toDate();
        canReuseExistingPuzzle = allowReuseExistingPuzzle &&
            _hasStoredReviewReadyPuzzleImage(existingData);
        existingPuzzlePath = existingData['puzzlePath'] as String? ?? '';
        existingPuzzleThumbnailPath =
            existingData['puzzleThumbnailPath'] as String? ??
                existingPuzzlePath;
      }
    } else {
      final latestLevel =
          await levelsRef.orderBy('nr', descending: true).limit(1).get();
      if (latestLevel.docs.isNotEmpty) {
        levelNr = (latestLevel.docs.first.data()['nr'] ?? 0) + 1;
      }
    }

    final storageBase = 'user-levels/$uid/${docRef.id}';
    final storedSolutionBytes = await compressStoredFactSolutionWebp(
      solutionPngBytes,
      failureLabel: 'solution image',
    );
    final solutionRef = _storage.ref('$storageBase/solution.webp');
    await solutionRef.putData(
      storedSolutionBytes,
      SettableMetadata(
        contentType: 'image/webp',
        customMetadata: <String, String>{
          'ownerUid': uid,
          'editorMode': UserLevelEditorMode.drawObject,
          'assetRole': 'solution',
        },
      ),
    );

    String puzzlePath = '';
    String puzzleThumbnailPath = '';
    bool hasPuzzleImage = false;

    if (puzzleImageBytes != null) {
      final puzzleAssets = await _buildPuzzleStorageAssets(puzzleImageBytes);
      final puzzleRef = _storage.ref('$storageBase/puzzle.webp');
      final puzzleThumbRef = _storage.ref('$storageBase/puzzle_thumb.webp');
      await puzzleRef.putData(
        puzzleAssets.imageBytes,
        SettableMetadata(
          contentType: 'image/webp',
          customMetadata: <String, String>{
            'ownerUid': uid,
            'editorMode': UserLevelEditorMode.drawObject,
            'assetRole': 'puzzle',
          },
        ),
      );
      await puzzleThumbRef.putData(
        puzzleAssets.thumbnailBytes,
        SettableMetadata(
          contentType: 'image/webp',
          customMetadata: <String, String>{
            'ownerUid': uid,
            'editorMode': UserLevelEditorMode.drawObject,
            'assetRole': 'puzzleThumbnail',
          },
        ),
      );
      puzzlePath = puzzleRef.fullPath;
      puzzleThumbnailPath = puzzleThumbRef.fullPath;
      hasPuzzleImage = true;
    } else if (canReuseExistingPuzzle) {
      puzzlePath = existingPuzzlePath;
      puzzleThumbnailPath = existingPuzzleThumbnailPath;
      hasPuzzleImage = puzzlePath.isNotEmpty;
    }

    final normalizedContentCategory = UserLevelContentCategory.normalize(
      contentCategory,
      editorMode: UserLevelEditorMode.drawObject,
    );
    final normalizedEditorData = Map<String, dynamic>.from(editorData)
      ..['contentCategory'] = normalizedContentCategory
      ..['hasPuzzleImage'] = hasPuzzleImage;

    await docRef.set(<String, dynamic>{
      'nr': levelNr,
      'name': answer.trim(),
      'hintType': 'fact',
      'editorMode': UserLevelEditorMode.drawObject,
      'contentCategory': normalizedContentCategory,
      'creatorUid': uid,
      'creatorName': creatorName.trim(),
      'hints': <String, dynamic>{'fact': factText.trim()},
      'puzzlePath': puzzlePath,
      'puzzleThumbnailPath': puzzleThumbnailPath,
      'solutionPath': solutionRef.fullPath,
      'tooltipStart': '',
      'tooltipEnd': '',
      'isEnabled': true,
      'isLocked': false,
      'submissionStatus': UserLevelSubmissionStatus.draft,
      'submissionId': null,
      'editorData': normalizedEditorData,
      'createdAt': existingCreatedAt == null
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(existingCreatedAt),
      'modifiedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return docRef.id;
  }

  Future<String> savePhotoSketchLevel({
    String? levelId,
    required String creatorName,
    required String answer,
    required String factText,
    required String contentCategory,
    required Uint8List sourceImageBytes,
    Uint8List? solutionImageBytes,
    Uint8List? puzzleImageBytes,
    bool allowReuseExistingPuzzle = true,
    bool persistSolutionAsset = false,
    required Map<String, dynamic> editorData,
  }) async {
    await assertUserCanCreateLevels();
    final uid = currentUserId;
    if (uid == null || uid.isEmpty) {
      throw StateError('You need to be signed in before saving a level.');
    }

    final levelsRef = _userLevelsCollection(uid);
    final docRef = levelId == null ? levelsRef.doc() : levelsRef.doc(levelId);

    int levelNr = 1;
    DateTime? existingCreatedAt;
    String existingSolutionPath = '';
    String existingSourcePath = '';
    String existingPuzzlePath = '';
    String existingPuzzleThumbnailPath = '';
    bool canReuseExistingPuzzle = false;

    if (levelId != null) {
      final existingDoc = await docRef.get();
      if (existingDoc.exists && existingDoc.data() != null) {
        final existingData = existingDoc.data()!;
        if (existingData['isLocked'] == true) {
          throw StateError(
              'Submitted levels are locked. Duplicate the level to change it.');
        }
        levelNr = existingData['nr'] ?? 1;
        existingCreatedAt = (existingData['createdAt'] as Timestamp?)?.toDate();
        existingSolutionPath = existingData['solutionPath'] as String? ?? '';
        existingSourcePath = (Map<String, dynamic>.from(
                  existingData['editorData'] ?? const <String, dynamic>{},
                )['sourceImagePath'] as String? ??
                '')
            .trim();
        canReuseExistingPuzzle = allowReuseExistingPuzzle &&
            _hasStoredReviewReadyPuzzleImage(existingData);
        existingPuzzlePath = existingData['puzzlePath'] as String? ?? '';
        existingPuzzleThumbnailPath =
            existingData['puzzleThumbnailPath'] as String? ??
                existingPuzzlePath;
      }
    } else {
      final latestLevel =
          await levelsRef.orderBy('nr', descending: true).limit(1).get();
      if (latestLevel.docs.isNotEmpty) {
        levelNr = (latestLevel.docs.first.data()['nr'] ?? 0) + 1;
      }
    }

    final storageBase = 'user-levels/$uid/${docRef.id}';
    final sanitizedSource = await _sanitizeAndStoreUserUpload(
      levelId: docRef.id,
      uploadKind: 'face_source',
      imageBytes: sourceImageBytes,
    );

    String solutionPath = '';
    if (persistSolutionAsset && solutionImageBytes != null) {
      final solutionRef = _storage.ref('$storageBase/solution.webp');
      await solutionRef.putData(
        solutionImageBytes,
        SettableMetadata(
          contentType: 'image/webp',
          customMetadata: <String, String>{
            'ownerUid': uid,
            'editorMode': UserLevelEditorMode.photoSketch,
            'assetRole': 'solution',
          },
        ),
      );
      solutionPath = solutionRef.fullPath;
    }

    String puzzlePath = '';
    String puzzleThumbnailPath = '';
    bool hasPuzzleImage = false;

    if (puzzleImageBytes != null) {
      final puzzleAssets = await _buildPuzzleStorageAssets(puzzleImageBytes);
      final puzzleRef = _storage.ref('$storageBase/puzzle.webp');
      final puzzleThumbRef = _storage.ref('$storageBase/puzzle_thumb.webp');
      await puzzleRef.putData(
        puzzleAssets.imageBytes,
        SettableMetadata(
          contentType: 'image/webp',
          customMetadata: <String, String>{
            'ownerUid': uid,
            'editorMode': UserLevelEditorMode.photoSketch,
            'assetRole': 'puzzle',
          },
        ),
      );
      await puzzleThumbRef.putData(
        puzzleAssets.thumbnailBytes,
        SettableMetadata(
          contentType: 'image/webp',
          customMetadata: <String, String>{
            'ownerUid': uid,
            'editorMode': UserLevelEditorMode.photoSketch,
            'assetRole': 'puzzleThumbnail',
          },
        ),
      );
      puzzlePath = puzzleRef.fullPath;
      puzzleThumbnailPath = puzzleThumbRef.fullPath;
      hasPuzzleImage = true;
    } else if (canReuseExistingPuzzle) {
      puzzlePath = existingPuzzlePath;
      puzzleThumbnailPath = existingPuzzleThumbnailPath;
      hasPuzzleImage = puzzlePath.isNotEmpty;
    }

    final normalizedContentCategory = UserLevelContentCategory.normalize(
      contentCategory,
      editorMode: UserLevelEditorMode.photoSketch,
    );
    final normalizedEditorData = Map<String, dynamic>.from(editorData)
      ..['contentCategory'] = normalizedContentCategory
      ..['hasPuzzleImage'] = hasPuzzleImage
      ..['sourceImagePath'] = sanitizedSource.storagePath
      ..['sourceImageContentType'] = sanitizedSource.contentType
      ..['sourceImageWidth'] = sanitizedSource.width
      ..['sourceImageHeight'] = sanitizedSource.height
      ..['sourceImageSizeBytes'] = sanitizedSource.sizeBytes
      ..['sourceImageSafetyStatus'] = sanitizedSource.safetyStatus
      ..['sourceImageNsfwCheckStatus'] = sanitizedSource.nsfwCheckStatus;

    await docRef.set(<String, dynamic>{
      'nr': levelNr,
      'name': answer.trim(),
      'hintType': 'fact',
      'editorMode': UserLevelEditorMode.photoSketch,
      'contentCategory': normalizedContentCategory,
      'creatorUid': uid,
      'creatorName': creatorName.trim(),
      'hints': <String, dynamic>{'fact': factText.trim()},
      'puzzlePath': puzzlePath,
      'puzzleThumbnailPath': puzzleThumbnailPath,
      'solutionPath': solutionPath,
      'sourceImageSafetyStatus': sanitizedSource.safetyStatus,
      'sourceImageNsfwCheckStatus': sanitizedSource.nsfwCheckStatus,
      'tooltipStart': '',
      'tooltipEnd': '',
      'isEnabled': true,
      'isLocked': false,
      'submissionStatus': UserLevelSubmissionStatus.draft,
      'submissionId': null,
      'editorData': normalizedEditorData,
      'createdAt': existingCreatedAt == null
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(existingCreatedAt),
      'modifiedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (!persistSolutionAsset && existingSolutionPath.isNotEmpty) {
      await _deleteStoragePathIfExists(existingSolutionPath);
    }
    if (existingSourcePath.isNotEmpty &&
        existingSourcePath != sanitizedSource.storagePath) {
      await _deleteStoragePathIfExists(existingSourcePath);
    }

    return docRef.id;
  }

  Future<void> deleteMyLevel(String levelId) async {
    final uid = currentUserId;
    if (uid == null || uid.isEmpty) {
      throw StateError('You need to be signed in before deleting a level.');
    }

    final docRef = _userLevelsCollection(uid).doc(levelId);
    final existingDoc = await docRef.get();
    if (!existingDoc.exists || existingDoc.data() == null) {
      return;
    }

    final levelData = existingDoc.data()!;
    if (levelData['isLocked'] == true) {
      throw StateError('Submitted levels are locked and cannot be deleted.');
    }

    final editorData =
        Map<String, dynamic>.from(levelData['editorData'] ?? const {});
    final storagePaths = <String>{
      levelData['solutionPath'] as String? ?? '',
      levelData['puzzlePath'] as String? ?? '',
      levelData['puzzleThumbnailPath'] as String? ?? '',
      editorData['sourceImagePath'] as String? ?? '',
      'user-levels/$uid/$levelId/source.jpg',
      'user-levels/$uid/$levelId/source.webp',
      'user-levels/$uid/$levelId/solution.webp',
      'user-levels/$uid/$levelId/solution.svg',
      'user-levels/$uid/$levelId/puzzle.webp',
      'user-levels/$uid/$levelId/puzzle_thumb.webp',
    }..removeWhere((path) => path.trim().isEmpty);

    for (final storagePath in storagePaths) {
      await _deleteStoragePathIfExists(storagePath);
    }

    await docRef.delete();
  }

  Future<String> saveWordLevel({
    String? levelId,
    required String creatorName,
    required String answer,
    required String factText,
    required String contentCategory,
    required String solutionSvg,
    Uint8List? puzzleImageBytes,
    bool allowReuseExistingPuzzle = true,
    required Map<String, dynamic> editorData,
  }) async {
    await assertUserCanCreateLevels();
    final uid = currentUserId;
    if (uid == null || uid.isEmpty) {
      throw StateError('You need to be signed in before saving a level.');
    }

    final levelsRef = _userLevelsCollection(uid);
    final docRef = levelId == null ? levelsRef.doc() : levelsRef.doc(levelId);

    int levelNr = 1;
    DateTime? existingCreatedAt;
    String existingPuzzlePath = '';
    String existingPuzzleThumbnailPath = '';
    bool canReuseExistingPuzzle = false;

    if (levelId != null) {
      final existingDoc = await docRef.get();
      if (existingDoc.exists && existingDoc.data() != null) {
        final existingData = existingDoc.data()!;
        if (existingData['isLocked'] == true) {
          throw StateError(
              'Submitted levels are locked. Duplicate the level to change it.');
        }
        levelNr = existingData['nr'] ?? 1;
        existingCreatedAt = (existingData['createdAt'] as Timestamp?)?.toDate();
        canReuseExistingPuzzle = allowReuseExistingPuzzle &&
            _hasStoredReviewReadyPuzzleImage(existingData);
        existingPuzzlePath = existingData['puzzlePath'] as String? ?? '';
        existingPuzzleThumbnailPath =
            existingData['puzzleThumbnailPath'] as String? ??
                existingPuzzlePath;
      }
    } else {
      final latestLevel =
          await levelsRef.orderBy('nr', descending: true).limit(1).get();
      if (latestLevel.docs.isNotEmpty) {
        levelNr = (latestLevel.docs.first.data()['nr'] ?? 0) + 1;
      }
    }

    final storageBase = 'user-levels/$uid/${docRef.id}';
    final solutionRef = _storage.ref('$storageBase/solution.svg');
    await solutionRef.putString(
      solutionSvg,
      format: PutStringFormat.raw,
      metadata: SettableMetadata(
        contentType: 'image/svg+xml',
        customMetadata: <String, String>{
          'ownerUid': uid,
          'editorMode': UserLevelEditorMode.highlight,
          'assetRole': 'solution',
        },
      ),
    );

    String puzzlePath = '';
    String puzzleThumbnailPath = '';
    bool hasPuzzleImage = false;

    if (puzzleImageBytes != null) {
      final puzzleAssets = await _buildPuzzleStorageAssets(puzzleImageBytes);
      final puzzleRef = _storage.ref('$storageBase/puzzle.webp');
      final puzzleThumbRef = _storage.ref('$storageBase/puzzle_thumb.webp');
      await puzzleRef.putData(
        puzzleAssets.imageBytes,
        SettableMetadata(
          contentType: 'image/webp',
          customMetadata: <String, String>{
            'ownerUid': uid,
            'editorMode': UserLevelEditorMode.highlight,
            'assetRole': 'puzzle',
          },
        ),
      );
      await puzzleThumbRef.putData(
        puzzleAssets.thumbnailBytes,
        SettableMetadata(
          contentType: 'image/webp',
          customMetadata: <String, String>{
            'ownerUid': uid,
            'editorMode': UserLevelEditorMode.highlight,
            'assetRole': 'puzzleThumbnail',
          },
        ),
      );
      puzzlePath = puzzleRef.fullPath;
      puzzleThumbnailPath = puzzleThumbRef.fullPath;
      hasPuzzleImage = true;
    } else if (canReuseExistingPuzzle) {
      puzzlePath = existingPuzzlePath;
      puzzleThumbnailPath = existingPuzzleThumbnailPath;
      hasPuzzleImage = puzzlePath.isNotEmpty;
    }

    final normalizedContentCategory = UserLevelContentCategory.normalize(
      contentCategory,
      editorMode: UserLevelEditorMode.highlight,
    );
    final normalizedEditorData = Map<String, dynamic>.from(editorData)
      ..['contentCategory'] = normalizedContentCategory
      ..['hasPuzzleImage'] = hasPuzzleImage;

    await docRef.set(<String, dynamic>{
      'nr': levelNr,
      'name': answer.trim(),
      'hintType': 'highlight',
      'editorMode': UserLevelEditorMode.highlight,
      'contentCategory': normalizedContentCategory,
      'creatorUid': uid,
      'creatorName': creatorName.trim(),
      'hints': factText.trim().isEmpty
          ? <String, dynamic>{}
          : <String, dynamic>{'fact': factText.trim()},
      'puzzlePath': puzzlePath,
      'puzzleThumbnailPath': puzzleThumbnailPath,
      'solutionPath': solutionRef.fullPath,
      'tooltipStart': '',
      'tooltipEnd': '',
      'isEnabled': true,
      'isLocked': false,
      'submissionStatus': UserLevelSubmissionStatus.draft,
      'submissionId': null,
      'editorData': normalizedEditorData,
      'createdAt': existingCreatedAt == null
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(existingCreatedAt),
      'modifiedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return docRef.id;
  }

  Future<String> submitUserLevelForReview(String levelId) async {
    await assertUserCanCreateLevels();
    try {
      final callable = _functions.httpsCallable('submitUserLevelSubmission');
      final response = await callable.call<Map<String, dynamic>>(
        <String, dynamic>{'levelId': levelId},
      );
      final responseData = Map<String, dynamic>.from(response.data);
      return responseData['submissionId'] as String? ?? '';
    } on FirebaseFunctionsException catch (error) {
      final parts = <String>[
        error.code.trim(),
        (error.message ?? '').trim(),
        if (error.details != null)
          error.details is String
              ? (error.details as String).trim()
              : jsonEncode(error.details),
      ].where((part) => part.isNotEmpty).toList();

      throw StateError(
        parts.isEmpty ? error.toString() : parts.join(' | '),
      );
    }
  }

  Future<Uint8List> generateDrawObjectPuzzle({
    required Uint8List solutionImageBytes,
    String solutionFileName = '1.png',
    String solutionMimeType = 'image/png',
    required String prompt,
    required double difficulty,
    String? existingJobId,
    void Function(String jobId)? onJobStarted,
    void Function(String status)? onStatusChanged,
  }) async {
    await assertUserCanCreateLevels();
    final requestBody = <String, dynamic>{
      'payload': <String, dynamic>{
        'input': <String, dynamic>{
          'workflow': _buildRunpodWorkflow(
            prompt: prompt,
            difficulty: difficulty,
            solutionFileName: solutionFileName,
          ),
          'images': <Map<String, String>>[
            <String, String>{
              'name': solutionFileName,
              'image':
                  'data:$solutionMimeType;base64,${base64Encode(solutionImageBytes)}',
            },
          ],
        },
      },
    };

    const maxWarmupRetries = 12;
    const maxTotalWait = Duration(minutes: 8);
    const warmupTimeoutMessage =
        'Puzzle generation is still preparing. You can leave this screen and come back to your draft.';
    final totalWait = Stopwatch()..start();
    var activeJobId = existingJobId?.trim();
    var warmupRetryCount = 0;
    onStatusChanged?.call(
      activeJobId == null || activeJobId.isEmpty
          ? 'Preparing puzzle...'
          : 'Resuming saved puzzle...',
    );

    while (warmupRetryCount <= maxWarmupRetries) {
      if (totalWait.elapsed >= maxTotalWait) {
        if (activeJobId != null && activeJobId.isNotEmpty) {
          throw PendingPuzzleGenerationException(
            jobId: activeJobId,
            message: warmupTimeoutMessage,
          );
        }
        throw StateError(warmupTimeoutMessage);
      }

      if (activeJobId == null || activeJobId.isEmpty) {
        if (warmupRetryCount > 0) {
          onStatusChanged?.call('Still preparing puzzle...');
        }

        final startData = await _startRunpodGeneration(
          requestBody: requestBody,
          onStatusChanged: onStatusChanged,
        );
        activeJobId = (startData['jobId'] as String? ?? '').trim();
        if (activeJobId.isEmpty) {
          throw StateError('The generation job did not start correctly.');
        }
        onJobStarted?.call(activeJobId);
      }

      var transientFailures = 0;
      var shouldRestartJob = false;
      for (var attempt = 0; attempt < 120; attempt += 1) {
        if (totalWait.elapsed >= maxTotalWait) {
          throw PendingPuzzleGenerationException(
            jobId: activeJobId!,
            message: warmupTimeoutMessage,
          );
        }

        await Future<void>.delayed(
          Duration(
            seconds: switch (attempt) {
              < 2 => 5,
              < 12 => 6,
              < 36 => 8,
              _ => 10,
            },
          ),
        );

        Map<String, dynamic> statusData;
        try {
          statusData = await _postRunpodProxy(
            '/api/generate-status',
            <String, dynamic>{'jobId': activeJobId},
          );
          transientFailures = 0;
        } catch (error, stackTrace) {
          if (_isTransientGenerationError(error) && transientFailures < 40) {
            transientFailures += 1;
            _log.warning(
              'Transient RunPod status polling error for job $activeJobId '
              '(attempt ${attempt + 1}, transient retry $transientFailures).',
              error,
              stackTrace,
            );
            onStatusChanged?.call('Still preparing puzzle...');
            continue;
          }
          rethrow;
        }

        final status = (statusData['status'] as String? ?? 'UNKNOWN').trim();
        onStatusChanged?.call(
          _friendlyGenerationStatus(
            status,
            retryable: statusData['retryable'] == true,
            generationAttempt: warmupRetryCount,
            elapsed: totalWait.elapsed,
          ),
        );

        if (status == 'COMPLETED') {
          final imageBase64 = statusData['imageBase64'] as String? ?? '';
          if (imageBase64.isEmpty) {
            throw StateError('Generation completed without an image.');
          }
          return _decodeGeneratedImage(imageBase64);
        }

        if (status == 'FAILED' || status == 'CANCELLED') {
          final details = (statusData['errorMessage'] as String? ?? '').trim();
          final retryable = _shouldRetryTerminalGenerationStatus(
            status: status,
            details: details,
            elapsed: totalWait.elapsed,
            generationAttempt: warmupRetryCount,
            proxyMarkedRetryable: statusData['retryable'] == true,
          );

          if (retryable && warmupRetryCount < maxWarmupRetries) {
            warmupRetryCount += 1;
            final retryAfterMs =
                (statusData['retryAfterMs'] as num?)?.round() ??
                    (warmupRetryCount < 3 ? 5000 : 9000);
            if (totalWait.elapsed + Duration(milliseconds: retryAfterMs) >=
                maxTotalWait) {
              throw PendingPuzzleGenerationException(
                jobId: activeJobId!,
                message: warmupTimeoutMessage,
              );
            }
            onStatusChanged?.call('Still preparing puzzle...');
            activeJobId = null;
            shouldRestartJob = true;
            await Future<void>.delayed(Duration(milliseconds: retryAfterMs));
            break;
          }

          if (details.isNotEmpty) {
            throw StateError('Puzzle generation failed: $details');
          }
          throw StateError('Puzzle generation failed.');
        }
      }

      if (!shouldRestartJob) {
        throw PendingPuzzleGenerationException(
          jobId: activeJobId!,
          message: warmupTimeoutMessage,
        );
      }
    }

    throw StateError(
      warmupTimeoutMessage,
    );
  }

  Future<Map<String, dynamic>> _startRunpodGeneration({
    required Map<String, dynamic> requestBody,
    void Function(String status)? onStatusChanged,
  }) async {
    Object? lastError;
    StackTrace? lastStackTrace;

    for (var attempt = 0; attempt < 8; attempt += 1) {
      try {
        if (attempt > 0) {
          onStatusChanged?.call('Still preparing puzzle...');
        }
        return await _postRunpodProxy(
          '/api/generate-run',
          requestBody,
          forceRefresh: attempt > 0,
        );
      } catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;
        if (!_isTransientGenerationError(error) || attempt == 7) {
          rethrow;
        }

        _log.warning(
          'Transient RunPod start error on attempt ${attempt + 1}.',
          error,
          stackTrace,
        );
        onStatusChanged?.call('Preparing puzzle...');
        await Future<void>.delayed(
          Duration(seconds: attempt < 2 ? 3 : 5 + attempt),
        );
      }
    }

    Error.throwWithStackTrace(
      lastError ?? StateError('The generation job did not start correctly.'),
      lastStackTrace ?? StackTrace.current,
    );
  }

  bool _isTransientGenerationError(Object error) {
    final message = switch (error) {
      StateError() => error.message.toString(),
      _ => error.toString(),
    }
        .toLowerCase();

    return message.contains('invalid response') ||
        message.contains('internal server error') ||
        message.contains('bad gateway') ||
        message.contains('gateway') ||
        message.contains('timed out') ||
        message.contains('timeout') ||
        message.contains('connection reset') ||
        message.contains('socket') ||
        message.contains('unexpected end') ||
        message.contains('job did not start correctly') ||
        message.contains('rate limit') ||
        message.contains('too many requests') ||
        message.contains('(404)') ||
        message.contains('(408)') ||
        message.contains('(409)') ||
        message.contains('(429)') ||
        message.contains('(500)') ||
        message.contains('(502)') ||
        message.contains('(503)') ||
        message.contains('(504)') ||
        message.contains('temporarily unavailable');
  }

  bool _isRetryableTerminalGenerationStatus(String status, String details) {
    if (status != 'FAILED' && status != 'CANCELLED') {
      return false;
    }

    final message = details.toLowerCase();
    return message.contains('failed to connect to server') ||
        message.contains('job did not start correctly') ||
        message.contains('bad gateway') ||
        message.contains('gateway') ||
        message.contains('no healthy upstream') ||
        message.contains('resource not ready') ||
        message.contains('temporarily unavailable') ||
        message.contains('service unavailable') ||
        message.contains('internal server error') ||
        message.contains('timed out') ||
        message.contains('timeout') ||
        message.contains('startup') ||
        message.contains('starting server') ||
        message.contains('starting handler') ||
        message.contains('starting worker') ||
        message.contains('handler') ||
        message.contains('warming') ||
        message.contains('initializing') ||
        message.contains('loading model') ||
        message.contains('loading') ||
        message.contains('boot');
  }

  bool _shouldRetryTerminalGenerationStatus({
    required String status,
    required String details,
    required Duration elapsed,
    required int generationAttempt,
    required bool proxyMarkedRetryable,
  }) {
    if (proxyMarkedRetryable ||
        _isRetryableTerminalGenerationStatus(status, details)) {
      return true;
    }

    // Treat early terminal states as warm-up noise unless they persist.
    if (elapsed < const Duration(minutes: 2, seconds: 30)) {
      return true;
    }

    if (details.trim().isEmpty && generationAttempt < 4) {
      return true;
    }

    final message = details.toLowerCase();
    return message.contains('unknown') ||
        message.contains('not ready') ||
        message.contains('not available');
  }

  String _friendlyGenerationStatus(
    String status, {
    required bool retryable,
    required int generationAttempt,
    required Duration elapsed,
  }) {
    switch (status.toUpperCase()) {
      case 'IN_QUEUE':
      case 'QUEUED':
        if (elapsed >= const Duration(seconds: 55)) {
          return 'Still preparing puzzle...';
        }
        return 'Preparing puzzle...';
      case 'IN_PROGRESS':
      case 'PROCESSING':
      case 'RUNNING':
        if (elapsed >= const Duration(seconds: 80)) {
          return 'Finishing puzzle...';
        }
        return generationAttempt == 0
            ? 'Creating puzzle...'
            : 'Still creating puzzle...';
      case 'COMPLETED':
        return 'Puzzle ready';
      case 'FAILED':
      case 'CANCELLED':
        return retryable
            ? 'Still preparing puzzle...'
            : 'Puzzle generation failed.';
      default:
        return generationAttempt == 0
            ? 'Preparing puzzle...'
            : 'Still preparing puzzle...';
    }
  }

  Uint8List _decodeGeneratedImage(String imageBase64) {
    final normalized =
        imageBase64.contains(',') ? imageBase64.split(',').last : imageBase64;
    return base64Decode(normalized);
  }

  Future<Map<String, dynamic>> _postRunpodProxy(
    String path,
    Map<String, dynamic> body, {
    bool forceRefresh = false,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final appCheckToken =
        await FirebaseAppCheck.instance.getToken(forceRefresh);
    if (appCheckToken == null || appCheckToken.isEmpty) {
      throw StateError(
          'Could not get an App Check token for puzzle generation.');
    }

    final idToken = currentUser == null
        ? null
        : await currentUser.getIdToken(forceRefresh);

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'X-Firebase-AppCheck': appCheckToken,
      if (idToken != null && idToken.trim().isNotEmpty)
        'Authorization': 'Bearer ${idToken.trim()}',
    };

    final response = await http.post(
      Uri.parse('$_runpodProxyBaseUrl$path'),
      headers: headers,
      body: jsonEncode(body),
    );

    if (response.statusCode == 401 && !forceRefresh) {
      return _postRunpodProxy(path, body, forceRefresh: true);
    }

    dynamic decoded = const <String, dynamic>{};
    if (response.body.isNotEmpty) {
      try {
        decoded = jsonDecode(response.body);
      } on FormatException {
        throw StateError(
          'Generation proxy returned an invalid response (${response.statusCode}).',
        );
      }
    }
    final json = decoded is Map<String, dynamic>
        ? decoded
        : Map<String, dynamic>.from(decoded as Map);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 413) {
        throw StateError(
          'The solution image is still too large for puzzle generation.',
        );
      }
      final errorMessage = json['error'] as String? ??
          'Puzzle generation request failed (${response.statusCode}).';
      throw StateError(errorMessage);
    }

    if (path == '/api/generate-run') {
      return <String, dynamic>{
        'jobId': (json['id'] as String? ?? '').trim(),
      };
    }

    return <String, dynamic>{
      'status': (json['status'] as String? ?? 'UNKNOWN').trim().toUpperCase(),
      'imageBase64': _extractGeneratedImage(json),
      'errorMessage': _extractGenerationError(json),
      'retryable': json['retryable'] == true,
      'retryAfterMs': (json['retryAfterMs'] as num?)?.round() ?? 0,
    };
  }

  Map<String, dynamic> _buildRunpodWorkflow({
    required String prompt,
    required double difficulty,
    required String solutionFileName,
  }) {
    return <String, dynamic>{
      '10': <String, dynamic>{
        'class_type': 'CheckpointLoaderSimple',
        'inputs': <String, dynamic>{
          'ckpt_name': 'Juggernaut-XL_v9_RunDiffusionPhoto_v2.safetensors',
        },
      },
      '11': <String, dynamic>{
        'class_type': 'CLIPTextEncode',
        'inputs': <String, dynamic>{
          'text': prompt,
          'clip': <dynamic>['10', 1],
        },
      },
      '14': <String, dynamic>{
        'class_type': 'ControlNetLoader',
        'inputs': <String, dynamic>{
          'control_net_name': 'diffusion_pytorch_model.safetensors',
        },
      },
      '15': <String, dynamic>{
        'class_type': 'CLIPTextEncode',
        'inputs': <String, dynamic>{
          'text': 'worst quality poor details unrealistic',
          'clip': <dynamic>['10', 1],
        },
      },
      '16': <String, dynamic>{
        'class_type': 'ControlNetApplyAdvanced',
        'inputs': <String, dynamic>{
          // Keep the uploaded drawing meaningfully in control of the result.
          'strength': difficulty.clamp(0.35, 2.0),
          'start_percent': 0.0,
          'end_percent': 1.0,
          'positive': <dynamic>['11', 0],
          'negative': <dynamic>['15', 0],
          'control_net': <dynamic>['14', 0],
          'image': <dynamic>['17', 0],
        },
      },
      '17': <String, dynamic>{
        'class_type': 'LoadImage',
        'inputs': <String, dynamic>{
          'image': solutionFileName,
          'upload': 'image',
        },
      },
      '18': <String, dynamic>{
        'class_type': 'KSampler',
        'inputs': <String, dynamic>{
          'seed': DateTime.now().microsecondsSinceEpoch,
          'steps': 20,
          'cfg': 8,
          'sampler_name': 'euler',
          'scheduler': 'normal',
          'denoise': 1.0,
          'model': <dynamic>['10', 0],
          'positive': <dynamic>['16', 0],
          'negative': <dynamic>['16', 1],
          'latent_image': <dynamic>['19', 0],
        },
      },
      '19': <String, dynamic>{
        'class_type': 'EmptyLatentImage',
        'inputs': <String, dynamic>{
          'width': 1024,
          'height': 1024,
          'batch_size': 1,
        },
      },
      '20': <String, dynamic>{
        'class_type': 'VAEDecode',
        'inputs': <String, dynamic>{
          'samples': <dynamic>['18', 0],
          'vae': <dynamic>['10', 2],
        },
      },
      '21': <String, dynamic>{
        'class_type': 'SaveImage',
        'inputs': <String, dynamic>{
          'filename_prefix': 'ComfyUI',
          'images': <dynamic>['20', 0],
        },
      },
    };
  }

  String _extractGeneratedImage(Map<String, dynamic> statusData) {
    final output = statusData['output'];
    if (output is Map) {
      final outputMap = Map<String, dynamic>.from(output);
      final images = outputMap['images'];
      if (images is List && images.isNotEmpty) {
        for (final image in images) {
          if (image is! Map) {
            continue;
          }
          final imageMap = Map<String, dynamic>.from(image);
          final value = (imageMap['data'] as String? ??
                  imageMap['image'] as String? ??
                  imageMap['url'] as String? ??
                  '')
              .trim();
          if (value.isNotEmpty) {
            return value;
          }
        }
      }

      final message = outputMap['message'];
      if (message is String) {
        return message.trim();
      }
    }

    if (output is List && output.isNotEmpty) {
      for (final item in output) {
        if (item is String && item.trim().isNotEmpty) {
          return item.trim();
        }
        if (item is! Map) {
          continue;
        }
        final itemMap = Map<String, dynamic>.from(item);
        final value = (itemMap['data'] as String? ??
                itemMap['image'] as String? ??
                itemMap['url'] as String? ??
                '')
            .trim();
        if (value.isNotEmpty) {
          return value;
        }
      }
    }

    return '';
  }

  String _extractGenerationError(Map<String, dynamic> statusData) {
    final directError = statusData['error'];
    if (directError is String && directError.trim().isNotEmpty) {
      return directError.trim();
    }

    final directMessage = statusData['message'];
    if (directMessage is String && directMessage.trim().isNotEmpty) {
      return directMessage.trim();
    }

    final output = statusData['output'];
    if (output is Map) {
      final outputMap = Map<String, dynamic>.from(output);
      for (final key in <String>['error', 'message', 'stderr', 'detail']) {
        final value = outputMap[key];
        if (value is String && value.trim().isNotEmpty) {
          return value.trim();
        }
      }
    }

    return '';
  }
}
