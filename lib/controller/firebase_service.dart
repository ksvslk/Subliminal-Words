import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
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

class PuzzleGenerationCancelledException implements Exception {
  final String message;

  const PuzzleGenerationCancelledException([
    this.message = 'Puzzle generation cancelled.',
  ]);

  @override
  String toString() => message;
}

class FirebaseService {
  static final _log = Logger('FirebaseService');
  static const String _creatorModerationCollection = 'creatorModeration';
  static const String _functionsRegion = 'us-central1';

  void _throwIfPuzzleGenerationCancelled(bool Function()? shouldCancel) {
    if (shouldCancel != null && shouldCancel()) {
      throw const PuzzleGenerationCancelledException();
    }
  }

  void _tracePuzzleGeneration(
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    final line = '[PuzzleGen] $message';
    if (error != null) {
      _log.warning(line, error, stackTrace);
    } else {
      _log.info(line);
    }
    debugPrint(line);
    if (error != null) {
      debugPrint('[PuzzleGen][error] $error');
    }
    if (stackTrace != null) {
      final stackPreview = stackTrace
          .toString()
          .split('\n')
          .take(4)
          .join('\n')
          .trim();
      if (stackPreview.isNotEmpty) {
        debugPrint('[PuzzleGen][stack] $stackPreview');
      }
    }
  }

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

  Future<SWLevel?> getLevel(String packId, dynamic levelId, {bool forceServer = false}) async {
    int maxRetries = 3;
    Duration delay = const Duration(seconds: 1);
    int attempt = 0;

    while (attempt < maxRetries) {
      try {
        final doc = await _db
            .collection('packs')
            .doc(packId)
            .collection('levels')
            .doc(levelId.toString())
            .get(forceServer ? const GetOptions(source: Source.server) : null);

        if (doc.exists && doc.data() != null) {
          return SWLevel.fromFirestore(doc.id, packId, doc.data()!);
        }
        _log.warning("[FirebaseService] Level doc not found: $packId/$levelId");
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
              "[FirebaseService] Failed to get level $packId/$levelId: $e");
          rethrow;
        }
      } catch (e, st) {
        _log.severe(
            "[FirebaseService] Unexpected error in getLevel: $packId/$levelId",
            e,
            st);
        rethrow;
      }
    }
    return null;
  }

  Future<SWLevel?> getLevelByPath(String path, {bool forceServer = false}) async {
    try {
      final doc = await _db
          .doc(path)
          .get(forceServer ? const GetOptions(source: Source.server) : null);

      if (doc.exists && doc.data() != null) {
        final parts = path.split('/');
        final packId = parts.length > 1 ? parts[1] : '';
        return SWLevel.fromFirestore(doc.id, packId, doc.data()!);
      }
    } catch (e) {
      _log.warning("[FirebaseService] Failed to get live level by path $path: $e");
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

  Future<void> persistPendingPuzzleGeneration({
    required String levelId,
    String? jobId,
  }) async {
    final uid = currentUserId;
    if (uid == null || uid.isEmpty || levelId.trim().isEmpty) {
      return;
    }

    final normalizedJobId = jobId?.trim();
    final now = DateTime.now().millisecondsSinceEpoch;
    final data = <String, dynamic>{
      'editorData.pendingPuzzleGeneration.status': 'running',
      'editorData.pendingPuzzleGeneration.updatedAt': now,
      'modifiedAt': FieldValue.serverTimestamp(),
    };

    if (normalizedJobId != null && normalizedJobId.isNotEmpty) {
      data['editorData.pendingPuzzleGeneration.jobId'] = normalizedJobId;
      data['editorData.pendingPuzzleGeneration.jobStartedAt'] = now;
    } else {
      data['editorData.pendingPuzzleGeneration.jobId'] = FieldValue.delete();
      data['editorData.pendingPuzzleGeneration.jobStartedAt'] =
          FieldValue.delete();
    }

    try {
      await _userLevelsCollection(uid).doc(levelId).update(data);
    } catch (_) {
      // Pending generation metadata is durability help, not a reason to fail
      // the main generation flow.
    }
  }

  Future<void> clearPendingPuzzleGeneration(String levelId) async {
    final uid = currentUserId;
    if (uid == null || uid.isEmpty || levelId.trim().isEmpty) {
      return;
    }

    try {
      await _userLevelsCollection(uid).doc(levelId).update(<String, dynamic>{
        'editorData.pendingPuzzleGeneration': FieldValue.delete(),
        'modifiedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Missing or already-cleared draft state should not block the flow.
    }
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
    final normalizedBytes = await prepareStoredPuzzleSourceJpeg(
      bytes,
      failureLabel: 'puzzle image',
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
      final ts = DateTime.now().millisecondsSinceEpoch;
      final puzzleRef = _storage.ref('$storageBase/puzzle_$ts.webp');
      final puzzleThumbRef = _storage.ref('$storageBase/puzzle_thumb_$ts.webp');
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
      'editorData.pendingPuzzleGeneration': FieldValue.delete(),
      'createdAt': existingCreatedAt == null
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(existingCreatedAt),
      'modifiedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (existingPuzzlePath.isNotEmpty && existingPuzzlePath != puzzlePath) {
      await _deleteStoragePathIfExists(existingPuzzlePath);
    }
    if (existingPuzzleThumbnailPath.isNotEmpty && existingPuzzleThumbnailPath != puzzleThumbnailPath) {
      await _deleteStoragePathIfExists(existingPuzzleThumbnailPath);
    }

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
    final normalizedContentCategory = UserLevelContentCategory.normalize(
      contentCategory,
      editorMode: UserLevelEditorMode.photoSketch,
    );

    int levelNr = 1;
    DateTime? existingCreatedAt;
    String existingSolutionPath = '';
    String existingSourcePath = '';
    String existingPuzzlePath = '';
    String existingPuzzleThumbnailPath = '';
    bool canReuseExistingPuzzle = false;
    bool draftDocExists = false;

    if (levelId != null) {
      final existingDoc = await docRef.get();
      if (existingDoc.exists && existingDoc.data() != null) {
        draftDocExists = true;
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
    final baseEditorData = Map<String, dynamic>.from(editorData)
      ..['contentCategory'] = normalizedContentCategory
      ..['hasPuzzleImage'] = false;

    var createdPlaceholderDraft = false;
    if (!draftDocExists) {
      await docRef.set(<String, dynamic>{
        'nr': levelNr,
        'name': answer.trim(),
        'hintType': 'fact',
        'editorMode': UserLevelEditorMode.photoSketch,
        'contentCategory': normalizedContentCategory,
        'creatorUid': uid,
        'creatorName': creatorName.trim(),
        'hints': <String, dynamic>{'fact': factText.trim()},
        'puzzlePath': '',
        'puzzleThumbnailPath': '',
        'solutionPath': '',
        'tooltipStart': '',
        'tooltipEnd': '',
        'isEnabled': true,
        'isLocked': false,
        'submissionStatus': UserLevelSubmissionStatus.draft,
        'submissionId': null,
        'editorData': baseEditorData,
        'editorData.pendingPuzzleGeneration': FieldValue.delete(),
        'createdAt': FieldValue.serverTimestamp(),
        'modifiedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      createdPlaceholderDraft = true;
    }

    _SanitizedUserUpload? sanitizedSource;
    String uploadedSolutionPath = '';
    String uploadedPuzzlePath = '';
    String uploadedPuzzleThumbnailPath = '';
    try {
      sanitizedSource = await _sanitizeAndStoreUserUpload(
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
        uploadedSolutionPath = solutionPath;
      }

      String puzzlePath = '';
      String puzzleThumbnailPath = '';
      bool hasPuzzleImage = false;

      if (puzzleImageBytes != null) {
        final puzzleAssets = await _buildPuzzleStorageAssets(puzzleImageBytes);
        final ts = DateTime.now().millisecondsSinceEpoch;
        final puzzleRef = _storage.ref('$storageBase/puzzle_$ts.webp');
        final puzzleThumbRef = _storage.ref('$storageBase/puzzle_thumb_$ts.webp');
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
        uploadedPuzzlePath = puzzlePath;
        uploadedPuzzleThumbnailPath = puzzleThumbnailPath;
        hasPuzzleImage = true;
      } else if (canReuseExistingPuzzle) {
        puzzlePath = existingPuzzlePath;
        puzzleThumbnailPath = existingPuzzleThumbnailPath;
        hasPuzzleImage = puzzlePath.isNotEmpty;
      }

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
        'editorData.pendingPuzzleGeneration': FieldValue.delete(),
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
      if (existingPuzzlePath.isNotEmpty && existingPuzzlePath != puzzlePath) {
        await _deleteStoragePathIfExists(existingPuzzlePath);
      }
      if (existingPuzzleThumbnailPath.isNotEmpty && existingPuzzleThumbnailPath != puzzleThumbnailPath) {
        await _deleteStoragePathIfExists(existingPuzzleThumbnailPath);
      }

      return docRef.id;
    } catch (error) {
      if (uploadedSolutionPath.isNotEmpty) {
        await _deleteStoragePathIfExists(uploadedSolutionPath);
      }
      if (uploadedPuzzlePath.isNotEmpty) {
        await _deleteStoragePathIfExists(uploadedPuzzlePath);
      }
      if (uploadedPuzzleThumbnailPath.isNotEmpty) {
        await _deleteStoragePathIfExists(uploadedPuzzleThumbnailPath);
      }
      final uploadedSourcePath = sanitizedSource?.storagePath ?? '';
      if (uploadedSourcePath.isNotEmpty &&
          uploadedSourcePath != existingSourcePath) {
        await _deleteStoragePathIfExists(uploadedSourcePath);
      }
      if (createdPlaceholderDraft) {
        try {
          await docRef.delete();
        } catch (_) {
          // If cleanup fails, the next save can still repair the draft.
        }
      }
      rethrow;
    }
  }

  Future<String> deleteMyLevel(String levelId) async {
    final uid = currentUserId;
    if (uid == null || uid.isEmpty) {
      throw StateError('You need to be signed in before deleting a level.');
    }

    try {
      final callable = _functions.httpsCallable('deleteUserLevelDraft');
      final response =
          await callable.call(<String, dynamic>{'levelId': levelId.trim()});
      final responseData =
          Map<String, dynamic>.from(response.data as Map? ?? const {});
      return (responseData['mode'] as String? ?? '').trim();
    } on FirebaseFunctionsException catch (error) {
      if (_shouldFallbackToDirectDraftDelete(error)) {
        return _deleteMyLevelLocally(levelId.trim());
      }
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

  bool _shouldFallbackToDirectDraftDelete(FirebaseFunctionsException error) {
    final code = error.code.trim().toLowerCase();
    final message = <String>[
      error.message ?? '',
      if (error.details != null)
        error.details is String ? error.details as String : jsonEncode(error.details),
    ].join(' ').toLowerCase();

    return code == 'not-found' ||
        code == 'unimplemented' ||
        message.contains('deleteuserleveldraft') ||
        message.contains('not found') ||
        message.contains('unimplemented');
  }

  Future<String> _deleteMyLevelLocally(String levelId) async {
    final uid = currentUserId;
    if (uid == null || uid.isEmpty) {
      throw StateError('You need to be signed in before deleting a level.');
    }

    final normalizedLevelId = levelId.trim();
    if (normalizedLevelId.isEmpty) {
      throw StateError('A levelId is required.');
    }

    final docRef = _userLevelsCollection(uid).doc(normalizedLevelId);
    final snapshot = await docRef.get();
    if (!snapshot.exists || snapshot.data() == null) {
      return 'missing';
    }

    final data = snapshot.data()!;
    final submissionStatus =
        '${data['submissionStatus'] ?? ''}'.trim().toLowerCase();
    final publicLevelPath = '${data['publicLevelPath'] ?? ''}'.trim();
    final isPublished = submissionStatus == 'approved' || publicLevelPath.isNotEmpty;

    final editorData =
        data['editorData'] is Map ? Map<String, dynamic>.from(data['editorData'] as Map) : const <String, dynamic>{};
    final storagePaths = <String>{
      '${data['solutionPath'] ?? ''}'.trim(),
      '${data['puzzlePath'] ?? ''}'.trim(),
      '${data['puzzleThumbnailPath'] ?? ''}'.trim(),
      '${editorData['sourceImagePath'] ?? ''}'.trim(),
    }..removeWhere((path) => path.isEmpty);

    await docRef.delete();
    for (final storagePath in storagePaths) {
      await _deleteStoragePathIfExists(storagePath);
    }

    return isPublished ? 'private_copy_deleted' : 'draft_deleted_local_only';
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
    
    String finalSolutionSvg = solutionSvg;
    if (editorData.containsKey('wordLetters')) {
      try {
        final callable = _functions.httpsCallable('formatWordLevelSvg');
        final res = await callable.call(<String, dynamic>{'letters': editorData['wordLetters']});
        final svgString = res.data['svg'] as String?;
        if (svgString != null && svgString.trim().isNotEmpty) {
          finalSolutionSvg = svgString;
        }
      } catch (e, st) {
        _log.warning('Failed to safely format word level SVG: $e, $st');
      }
    }

    await solutionRef.putString(
      finalSolutionSvg,
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
      final ts = DateTime.now().millisecondsSinceEpoch;
      final puzzleRef = _storage.ref('$storageBase/puzzle_$ts.webp');
      final puzzleThumbRef = _storage.ref('$storageBase/puzzle_thumb_$ts.webp');
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
      'editorData.pendingPuzzleGeneration': FieldValue.delete(),
      'createdAt': existingCreatedAt == null
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(existingCreatedAt),
      'modifiedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (existingPuzzlePath.isNotEmpty && existingPuzzlePath != puzzlePath) {
      await _deleteStoragePathIfExists(existingPuzzlePath);
    }
    if (existingPuzzleThumbnailPath.isNotEmpty && existingPuzzleThumbnailPath != puzzleThumbnailPath) {
      await _deleteStoragePathIfExists(existingPuzzleThumbnailPath);
    }

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

  Future<void> cancelPuzzleGeneration(String jobId) async {
    final normalizedJobId = jobId.trim();
    if (normalizedJobId.isEmpty) {
      return;
    }
    _tracePuzzleGeneration('proxy-cancel jobId=$normalizedJobId (stubbed)');
  }

  Future<void> startDrawObjectPuzzleGeneration({
    required Uint8List solutionImageBytes,
    String solutionFileName = '1.png',
    String solutionMimeType = 'image/png',
    required String prompt,
    required double difficulty,
    required String levelId,
    Future<void> Function(String jobId)? onJobStarted,
    void Function(String status)? onStatusChanged,
    bool Function()? shouldCancel,
  }) async {
    await assertUserCanCreateLevels();
    _throwIfPuzzleGenerationCancelled(shouldCancel);
    _tracePuzzleGeneration(
      'start level=$levelId mime=$solutionMimeType file=$solutionFileName difficulty=${difficulty.toStringAsFixed(2)}',
    );
    final solutionImageBase64 =
        'data:$solutionMimeType;base64,${base64Encode(solutionImageBytes)}';

    onStatusChanged?.call('Preparing puzzle');

    final startData = await _startPuzzleGenerationViaCallable(
      prompt: prompt,
      difficulty: difficulty,
      solutionImageBase64: solutionImageBase64,
      solutionFileName: solutionFileName,
      levelId: levelId,
      shouldCancel: shouldCancel,
    );
    
    _throwIfPuzzleGenerationCancelled(shouldCancel);
    final activeJobId = (startData['jobId'] as String? ?? '').trim();
    if (activeJobId.isEmpty) {
      throw StateError('The generation job did not start correctly.');
    }
    
    if (onJobStarted != null) {
      await onJobStarted(activeJobId);
    }
    
    _tracePuzzleGeneration('job-started level=$levelId jobId=$activeJobId');
  }

  Future<Map<String, dynamic>> _startPuzzleGenerationViaCallable({
    required String prompt,
    required double difficulty,
    required String solutionImageBase64,
    required String solutionFileName,
    required String levelId,
    bool Function()? shouldCancel,
  }) async {
    _throwIfPuzzleGenerationCancelled(shouldCancel);

    try {
      final callable = _functions.httpsCallable('startUserLevelPuzzleGeneration');
      final response = await callable.call<Map<String, dynamic>>(<String, dynamic>{
        'prompt': prompt,
        'difficulty': difficulty,
        'solutionImageBase64': solutionImageBase64,
        'solutionFileName': solutionFileName,
        'levelId': levelId.trim(),
      });
      final data = Map<String, dynamic>.from(response.data);
      return <String, dynamic>{
        'jobId': (data['jobId'] as String? ?? '').trim(),
        'reusedExisting': data['reusedExisting'] == true,
      };
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



  bool _isTransientGenerationError(Object error) {
    final message = switch (error) {
      StateError() => error.message.toString(),
      _ => error.toString(),
    }
        .toLowerCase();

    if (message.contains('today\'s puzzle generation limit') ||
        message.contains('another puzzle generation is already running') ||
        message.contains('please wait a moment before starting another puzzle')) {
      return false;
    }

    return message.contains('invalid response') ||
        message.contains('bad request') ||
        message.contains('internal server error') ||
        message.contains('bad gateway') ||
        message.contains('gateway') ||
        message.contains('failed to connect to server') ||
        message.contains('starting server') ||
        message.contains('starting worker') ||
        message.contains('starting handler') ||
        message.contains('warming') ||
        message.contains('initializing') ||
        message.contains('loading model') ||
        message.contains('boot') ||
        message.contains('timed out') ||
        message.contains('timeout') ||
        message.contains('connection reset') ||
        message.contains('socket') ||
        message.contains('unexpected end') ||
        message.contains('job did not start correctly') ||
        message.contains('rate limit') ||
        message.contains('too many requests') ||
        message.contains('sign-in is still restoring') ||
        message.contains('app security verification is still preparing') ||
        message.contains('invalid appcheck token') ||
        message.contains('must provide a valid appcheck token') ||
        message.contains('invalid firebase auth token') ||
        message.contains('must provide a firebase auth token') ||
        message.contains('unauthorized: invalid firebase auth token') ||
        message.contains('unauthorized: invalid appcheck token') ||
        message.contains('(404)') ||
        message.contains('(408)') ||
        message.contains('(409)') ||
        message.contains('(429)') ||
        message.contains('(500)') ||
        message.contains('(502)') ||
        message.contains('(503)') ||
        message.contains('(504)') ||
        message.contains('401: unauthorized') ||
        message.contains('internal server error polling runpod') ||
        message.contains('internal server error fetching runpod') ||
        message.contains('comfyui server') ||
        message.contains('not reachable after multiple retries') ||
        message.contains('127.0.0.1:8188') ||
        message.contains('503:') ||
        message.contains('504:') ||
        message.contains('temporarily unavailable');
  }

  bool _isClearlyPermanentStartGenerationError(Object error) {
    final message = switch (error) {
      StateError() => error.message.toString(),
      _ => error.toString(),
    }.toLowerCase();

    return message.contains('too large') ||
        message.contains('(413)') ||
        message.contains('payload') ||
        message.contains('unsupported image') ||
        message.contains('unsupported upload kind') ||
        message.contains('invalid image') ||
        message.contains('corrupt') ||
        message.contains('unreadable') ||
        message.contains('malformed') ||
        message.contains('only jpg, png, or webp');
  }

  bool _shouldTreatGenerationErrorAsPending(Object error) {
    final message = switch (error) {
      StateError() => error.message.toString(),
      _ => error.toString(),
    }.toLowerCase();

    return _isTransientGenerationError(error) ||
        message.contains('still preparing') ||
        message.contains('still starting') ||
        message.contains('checking saved puzzle') ||
        message.contains('preparing puzzle') ||
        message.contains('comfyui server') ||
        message.contains('not reachable after multiple retries') ||
        message.contains('127.0.0.1:8188');
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
        message.contains('job not found') ||
        message.contains('not found') ||
        message.contains('comfyui server') ||
        message.contains('not reachable after multiple retries') ||
        message.contains('127.0.0.1:8188') ||
        message.contains('boot');
  }

  bool _isClearlyPermanentGenerationFailureDetails(String details) {
    final message = details.trim().toLowerCase();
    if (message.isEmpty) {
      return false;
    }

    return message.contains('too large') ||
        message.contains('(413)') ||
        message.contains('payload') ||
        message.contains('unsupported') ||
        message.contains('invalid image') ||
        message.contains('corrupt') ||
        message.contains('unreadable') ||
        message.contains('malformed');
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

    if (_isClearlyPermanentGenerationFailureDetails(details)) {
      return false;
    }

    // Treat early and mid-run terminal states as warm-up noise unless they persist.
    if (elapsed < const Duration(minutes: 5)) {
      return true;
    }

    if (details.trim().isEmpty && generationAttempt < 8) {
      return true;
    }

    final message = details.toLowerCase();
    return message.contains('unknown') ||
        message.contains('not ready') ||
        message.contains('job not found') ||
        message.contains('not found') ||
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
        if (elapsed > const Duration(seconds: 40)) {
          return 'Still preparing puzzle';
        }
        return 'Preparing puzzle';
      case 'IN_PROGRESS':
      case 'PROCESSING':
      case 'RUNNING':
        if (elapsed >= const Duration(seconds: 80)) {
          return 'Finishing puzzle';
        }

        return elapsed < const Duration(seconds: 20)
            ? 'Creating puzzle'
            : 'Still creating puzzle';
      case 'COMPLETED':
        return 'Puzzle ready';
      case 'FAILED':
      case 'CANCELLED':
        return retryable
            ? 'Still preparing puzzle'
            : 'Uploading image';
      default:
        return elapsed < const Duration(seconds: 40)
            ? 'Preparing puzzle'
            : 'Still preparing puzzle';
    }
  }

  Uint8List _decodeGeneratedImage(String imageBase64) {
    final normalized =
        imageBase64.contains(',') ? imageBase64.split(',').last : imageBase64;
    return base64Decode(normalized);
  }
}
