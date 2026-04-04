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
  static const String _runpodProxyBaseUrl =
      'https://runpod-proxy-549374376791.us-central1.run.app';
  static const bool _preferDirectRunpodProxyForPuzzleGeneration = true;

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
      'editorData.pendingPuzzleGeneration': FieldValue.delete(),
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
      'editorData.pendingPuzzleGeneration': FieldValue.delete(),
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

  Future<void> cancelPuzzleGeneration(String jobId) async {
    final normalizedJobId = jobId.trim();
    if (normalizedJobId.isEmpty) {
      return;
    }

    _tracePuzzleGeneration('proxy-cancel jobId=$normalizedJobId');
    await _postRunpodProxy(
      '/api/generate-cancel',
      <String, dynamic>{'jobId': normalizedJobId},
    );
  }

  Future<Uint8List> generateDrawObjectPuzzle({
    required Uint8List solutionImageBytes,
    String solutionFileName = '1.png',
    String solutionMimeType = 'image/png',
    required String prompt,
    required double difficulty,
    required String levelId,
    String? existingJobId,
    Future<void> Function(String jobId)? onJobStarted,
    Future<void> Function(String jobId)? onPendingJobInvalidated,
    void Function(String status)? onStatusChanged,
    bool Function()? shouldCancel,
  }) async {
    await assertUserCanCreateLevels();
    _throwIfPuzzleGenerationCancelled(shouldCancel);
    _tracePuzzleGeneration(
      'start level=$levelId '
      'existingJobId=${existingJobId?.trim().isNotEmpty == true ? existingJobId!.trim() : '-'} '
      'mime=$solutionMimeType file=$solutionFileName '
      'bytes=${solutionImageBytes.length} difficulty=${difficulty.toStringAsFixed(2)}',
    );
    final solutionImageBase64 =
        'data:$solutionMimeType;base64,${base64Encode(solutionImageBytes)}';

    const maxWarmupRetries = 16;
    const maxTotalWait = Duration(minutes: 10);
    const warmupTimeoutMessage =
        'Puzzle generation is still preparing. Please keep this screen open a little longer.';
    final totalWait = Stopwatch()..start();
    final normalizedLevelId = levelId.trim();
    if (normalizedLevelId.isEmpty) {
      throw StateError('A draft id is required before generating a puzzle.');
    }
    var activeJobId = existingJobId?.trim();
    var activeJobWasReused = activeJobId != null && activeJobId.isNotEmpty;
    var warmupRetryCount = 0;
    var didClearStalePendingJob = false;
    onStatusChanged?.call(
      activeJobId == null || activeJobId.isEmpty
          ? 'Preparing puzzle...'
          : 'Resuming saved puzzle...',
    );

    while (warmupRetryCount <= maxWarmupRetries) {
      _throwIfPuzzleGenerationCancelled(shouldCancel);
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
          prompt: prompt,
          difficulty: difficulty,
          solutionImageBase64: solutionImageBase64,
          solutionFileName: solutionFileName,
          levelId: levelId,
          onStatusChanged: onStatusChanged,
          shouldCancel: shouldCancel,
        );
        _throwIfPuzzleGenerationCancelled(shouldCancel);
        activeJobId = (startData['jobId'] as String? ?? '').trim();
        activeJobWasReused = startData['reusedExisting'] == true;
        if (activeJobId.isEmpty) {
          throw StateError('The generation job did not start correctly.');
        }
        if (onJobStarted != null) {
          await onJobStarted(activeJobId);
        }
        _tracePuzzleGeneration(
          'job-ready level=$levelId jobId=$activeJobId '
          'reused=${activeJobWasReused ? 'yes' : 'no'}',
        );
      }

      var transientFailures = 0;
      var shouldRestartJob = false;
      for (var attempt = 0; attempt < 120; attempt += 1) {
        _throwIfPuzzleGenerationCancelled(shouldCancel);
        if (totalWait.elapsed >= maxTotalWait) {
          throw PendingPuzzleGenerationException(
            jobId: activeJobId!,
            message: warmupTimeoutMessage,
          );
        }

        await Future<void>.delayed(
          Duration(
            seconds: switch (attempt) {
              < 2 => 6,
              < 10 => 8,
              < 30 => 10,
              _ => 12,
            },
          ),
        );
        _throwIfPuzzleGenerationCancelled(shouldCancel);

        Map<String, dynamic> statusData;
        try {
          statusData = await _getPuzzleGenerationStatusViaCallable(
            activeJobId!,
            normalizedLevelId,
            shouldCancel: shouldCancel,
          );
          _throwIfPuzzleGenerationCancelled(shouldCancel);
          transientFailures = 0;
        } catch (error, stackTrace) {
          if (_isTransientGenerationError(error) && transientFailures < 40) {
            transientFailures += 1;
            _tracePuzzleGeneration(
              'transient-status-error level=$levelId jobId=$activeJobId '
              'attempt=${attempt + 1} transientRetry=$transientFailures',
              error: error,
              stackTrace: stackTrace,
            );
            onStatusChanged?.call('Still preparing puzzle...');
            continue;
          }
          if (_shouldTreatGenerationErrorAsPending(error)) {
            _tracePuzzleGeneration(
              'keeping-pending-after-status-error '
              'level=$levelId jobId=$activeJobId',
              error: error,
              stackTrace: stackTrace,
            );
            throw PendingPuzzleGenerationException(
              jobId: activeJobId!,
              message: warmupTimeoutMessage,
            );
          }
          rethrow;
        }

        final status = (statusData['status'] as String? ?? 'UNKNOWN').trim();
        _tracePuzzleGeneration(
          'status level=$levelId jobId=$activeJobId '
          'status=$status retryable=${statusData['retryable'] == true} '
          'error="${(statusData['errorMessage'] as String? ?? '').trim()}"',
        );
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
            _tracePuzzleGeneration(
              'completed-without-image level=$levelId jobId=$activeJobId',
            );
            throw StateError('Generation completed without an image.');
          }
          _tracePuzzleGeneration(
            'completed level=$levelId jobId=$activeJobId '
            'imageChars=${imageBase64.length}',
          );
          return _decodeGeneratedImage(imageBase64);
        }

        if (status == 'FAILED' || status == 'CANCELLED') {
          final details = (statusData['errorMessage'] as String? ?? '').trim();
          final permanentFailure =
              _isClearlyPermanentGenerationFailureDetails(details);
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
                jobId: activeJobId,
                message: warmupTimeoutMessage,
              );
            }
            onStatusChanged?.call('Still preparing puzzle...');
            activeJobId = null;
            shouldRestartJob = true;
            await Future<void>.delayed(Duration(milliseconds: retryAfterMs));
            _throwIfPuzzleGenerationCancelled(shouldCancel);
            break;
          }

          if (activeJobWasReused && !didClearStalePendingJob) {
            didClearStalePendingJob = true;
            if (onPendingJobInvalidated != null) {
              await onPendingJobInvalidated(activeJobId);
            }
            onStatusChanged?.call('Restarting puzzle...');
            activeJobId = null;
            activeJobWasReused = false;
            shouldRestartJob = true;
            break;
          }

          if (details.isNotEmpty) {
            _tracePuzzleGeneration(
              'terminal-failure level=$levelId jobId=$activeJobId '
              'status=$status permanent=$permanentFailure details="$details"',
            );
            if (!permanentFailure && activeJobId.isNotEmpty) {
              throw PendingPuzzleGenerationException(
                jobId: activeJobId,
                message: warmupTimeoutMessage,
              );
            }
            throw StateError('Puzzle generation failed: $details');
          }
          _tracePuzzleGeneration(
            'terminal-failure level=$levelId jobId=$activeJobId '
            'status=$status permanent=$permanentFailure without-details',
          );
          if (!permanentFailure && activeJobId.isNotEmpty) {
            throw PendingPuzzleGenerationException(
              jobId: activeJobId,
              message: warmupTimeoutMessage,
            );
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
    required String prompt,
    required double difficulty,
    required String solutionImageBase64,
    required String solutionFileName,
    required String levelId,
    void Function(String status)? onStatusChanged,
    bool Function()? shouldCancel,
  }) async {
    Object? lastError;
    StackTrace? lastStackTrace;

    for (var attempt = 0; attempt < 24; attempt += 1) {
      _throwIfPuzzleGenerationCancelled(shouldCancel);
      try {
        if (attempt > 0) {
          onStatusChanged?.call('Still preparing puzzle...');
        }
        return await _startPuzzleGenerationViaCallable(
          prompt: prompt,
          difficulty: difficulty,
          solutionImageBase64: solutionImageBase64,
          solutionFileName: solutionFileName,
          levelId: levelId,
          shouldCancel: shouldCancel,
        );
      } catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;
        final permanentlyInvalidStart =
            _isClearlyPermanentStartGenerationError(error);
        if (permanentlyInvalidStart) {
          rethrow;
        }
        if (attempt == 23) {
          throw PendingPuzzleGenerationException(
            jobId: '',
            message:
                'Puzzle generation is still preparing. Please keep this screen open a little longer.',
          );
        }
        if (!_isTransientGenerationError(error)) {
          _tracePuzzleGeneration(
            'treating-start-error-as-warmup attempt=${attempt + 1}',
            error: error,
            stackTrace: stackTrace,
          );
        } else {
          _tracePuzzleGeneration(
            'transient-start-error attempt=${attempt + 1}',
            error: error,
            stackTrace: stackTrace,
          );
        }
        onStatusChanged?.call('Preparing puzzle...');
        await Future<void>.delayed(
          Duration(
            seconds: switch (attempt) {
              < 2 => 5,
              < 6 => 8,
              < 12 => 12,
              < 18 => 16,
              _ => 20,
            },
          ),
        );
        _throwIfPuzzleGenerationCancelled(shouldCancel);
      }
    }

    Error.throwWithStackTrace(
      lastError ?? StateError('The generation job did not start correctly.'),
      lastStackTrace ?? StackTrace.current,
    );
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
    if (_preferDirectRunpodProxyForPuzzleGeneration) {
      return _startPuzzleGenerationViaProxy(
        prompt: prompt,
        difficulty: difficulty,
        solutionImageBase64: solutionImageBase64,
        solutionFileName: solutionFileName,
        shouldCancel: shouldCancel,
      );
    }

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
      if (_shouldFallbackToDirectRunpodProxy(error)) {
        _log.warning(
          'Falling back to direct RunPod proxy start because the generation '
          'callable is unavailable.',
          error,
        );
        return _startPuzzleGenerationViaProxy(
          prompt: prompt,
          difficulty: difficulty,
          solutionImageBase64: solutionImageBase64,
          solutionFileName: solutionFileName,
          shouldCancel: shouldCancel,
        );
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

  Future<Map<String, dynamic>> _getPuzzleGenerationStatusViaCallable(
    String jobId,
    String levelId,
    {bool Function()? shouldCancel,}
  ) async {
    _throwIfPuzzleGenerationCancelled(shouldCancel);
    if (_preferDirectRunpodProxyForPuzzleGeneration) {
      return _getPuzzleGenerationStatusViaProxy(
        jobId,
        shouldCancel: shouldCancel,
      );
    }

    try {
      final callable =
          _functions.httpsCallable('getUserLevelPuzzleGenerationStatus');
      final response = await callable.call<Map<String, dynamic>>(
        <String, dynamic>{
          'jobId': jobId,
          'levelId': levelId.trim(),
        },
      );
      final data = Map<String, dynamic>.from(response.data);
      return <String, dynamic>{
        'status': (data['status'] as String? ?? 'UNKNOWN').trim().toUpperCase(),
        'imageBase64': (data['imageBase64'] as String? ?? '').trim(),
        'errorMessage': (data['errorMessage'] as String? ?? '').trim(),
        'retryable': data['retryable'] == true,
        'retryAfterMs': (data['retryAfterMs'] as num?)?.round() ?? 0,
      };
    } on FirebaseFunctionsException catch (error) {
      if (_shouldFallbackToDirectRunpodProxy(error)) {
        _log.warning(
          'Falling back to direct RunPod proxy status polling because the '
          'generation callable is unavailable.',
          error,
        );
        return _getPuzzleGenerationStatusViaProxy(jobId);
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

  bool _shouldFallbackToDirectRunpodProxy(FirebaseFunctionsException error) {
    final code = error.code.trim().toLowerCase();
    final message = [
      error.message ?? '',
      if (error.details != null)
        error.details is String ? error.details as String : jsonEncode(error.details),
    ].join(' ').toLowerCase();

    return code == 'not-found' ||
        code == 'unimplemented' ||
        message.contains('startuserlevelpuzzlegeneration') ||
        message.contains('getuserlevelpuzzlegenerationstatus') ||
        message.contains('not found') ||
        message.contains('unimplemented');
  }

  Future<Map<String, dynamic>> _startPuzzleGenerationViaProxy({
    required String prompt,
    required double difficulty,
    required String solutionImageBase64,
    required String solutionFileName,
    bool Function()? shouldCancel,
  }) async {
    _throwIfPuzzleGenerationCancelled(shouldCancel);
    _tracePuzzleGeneration(
      'proxy-start file=$solutionFileName '
      'difficulty=${difficulty.toStringAsFixed(2)} payloadChars=${solutionImageBase64.length}',
    );
    final response = await _postRunpodProxy(
      '/api/generate-run',
      <String, dynamic>{
        'payload': <String, dynamic>{
          'input': <String, dynamic>{
            'workflow': _buildRunpodWorkflow(
              prompt,
              difficulty,
              solutionFileName,
            ),
            'images': <Map<String, dynamic>>[
              <String, dynamic>{
                'name': solutionFileName,
                'image': solutionImageBase64,
              },
            ],
          },
        },
      },
      shouldCancel: shouldCancel,
    );

    _throwIfPuzzleGenerationCancelled(shouldCancel);
    _tracePuzzleGeneration(
      'proxy-start-returned id=${'${response['id'] ?? ''}'.trim()}',
    );
    return <String, dynamic>{
      'jobId': '${response['id'] ?? ''}'.trim(),
      'reusedExisting': false,
    };
  }

  Future<Map<String, dynamic>> _getPuzzleGenerationStatusViaProxy(
    String jobId,
    {bool Function()? shouldCancel,}
  ) async {
    _throwIfPuzzleGenerationCancelled(shouldCancel);
    _tracePuzzleGeneration('proxy-status jobId=$jobId');
    final response = await _postRunpodProxy(
      '/api/generate-status',
      <String, dynamic>{'jobId': jobId},
      shouldCancel: shouldCancel,
    );
    _throwIfPuzzleGenerationCancelled(shouldCancel);
    return <String, dynamic>{
      'status': '${response['status'] ?? 'UNKNOWN'}'.trim().toUpperCase(),
      'imageBase64': _extractGeneratedImage(response),
      'errorMessage': _extractGenerationError(response),
      'retryable': response['retryable'] == true,
      'retryAfterMs': (response['retryAfterMs'] as num?)?.round() ?? 0,
    };
  }

  Future<Map<String, dynamic>> _postRunpodProxy(
    String path,
    Map<String, dynamic> body,
    {bool Function()? shouldCancel,}
  ) async {
    Object? lastError;
    StackTrace? lastStackTrace;

    for (var attempt = 0; attempt < 12; attempt += 1) {
      _throwIfPuzzleGenerationCancelled(shouldCancel);
      try {
        final authToken = await _getReliableFirebaseAuthToken(
          forceRefresh: attempt > 0,
          shouldCancel: shouldCancel,
        );
        final appCheckToken = await _getReliableAppCheckToken(
          forceRefresh: attempt > 0,
          shouldCancel: shouldCancel,
        );
        _throwIfPuzzleGenerationCancelled(shouldCancel);

        final response = await http.post(
          Uri.parse('$_runpodProxyBaseUrl$path'),
          headers: <String, String>{
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $authToken',
            'X-Firebase-AppCheck': appCheckToken,
          },
          body: jsonEncode(body),
        );
        _throwIfPuzzleGenerationCancelled(shouldCancel);

        final decoded = jsonDecode(response.body);
        if (decoded is! Map) {
          throw StateError('The generation service returned an invalid response.');
        }
        final data = Map<String, dynamic>.from(decoded);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          final message =
              '${data['error'] ?? 'Generation request failed.'}'.trim();
          final fullMessage = '${response.statusCode}: $message';
          _tracePuzzleGeneration('proxy-http-failure path=$path message=$fullMessage');
          if (_shouldRetryRunpodProxyResponse(
                statusCode: response.statusCode,
                message: fullMessage,
              ) &&
              attempt < 11) {
            await Future<void>.delayed(
              Duration(
                milliseconds: switch (attempt) {
                  < 2 => 1200,
                  < 6 => 2400 + attempt * 600,
                  _ => 5200 + attempt * 900,
                },
              ),
            );
            _throwIfPuzzleGenerationCancelled(shouldCancel);
            continue;
          }
          throw StateError(fullMessage);
        }
        if ('${data['error'] ?? ''}'.trim().isNotEmpty) {
          final message = '${data['error']}'.trim();
          _tracePuzzleGeneration('proxy-error path=$path message="$message"');
          if (_shouldRetryRunpodProxyResponse(
                statusCode: response.statusCode,
                message: message,
              ) &&
              attempt < 11) {
            await Future<void>.delayed(
              Duration(
                milliseconds: switch (attempt) {
                  < 2 => 1200,
                  < 6 => 2400 + attempt * 600,
                  _ => 5200 + attempt * 900,
                },
              ),
            );
            _throwIfPuzzleGenerationCancelled(shouldCancel);
            continue;
          }
          throw StateError(message);
        }
        _tracePuzzleGeneration(
          'proxy-success path=$path keys=${data.keys.join(',')}',
        );
        return data;
      } catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;
        _tracePuzzleGeneration(
          'proxy-attempt-failed path=$path attempt=${attempt + 1}',
          error: error,
          stackTrace: stackTrace,
        );
        if (!_isTransientGenerationError(error) || attempt == 11) {
          rethrow;
        }
        await Future<void>.delayed(
          Duration(
            milliseconds: switch (attempt) {
              < 2 => 1200,
              < 6 => 2400 + attempt * 600,
              _ => 5200 + attempt * 900,
            },
          ),
        );
        _throwIfPuzzleGenerationCancelled(shouldCancel);
      }
    }

    Error.throwWithStackTrace(
      lastError ?? StateError('Could not contact the generation service.'),
      lastStackTrace ?? StackTrace.current,
    );
  }

  Future<String> _getReliableFirebaseAuthToken({
    required bool forceRefresh,
    bool Function()? shouldCancel,
  }) async {
    for (var attempt = 0; attempt < 12; attempt += 1) {
      _throwIfPuzzleGenerationCancelled(shouldCancel);
      var currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        currentUser = await FirebaseAuth.instance
            .authStateChanges()
            .firstWhere((user) => user != null)
            .timeout(
              const Duration(seconds: 3),
              onTimeout: () => null,
            );
        _throwIfPuzzleGenerationCancelled(shouldCancel);
      }

      if (currentUser != null) {
        final token = await currentUser.getIdToken(forceRefresh || attempt > 0);
        _throwIfPuzzleGenerationCancelled(shouldCancel);
        if (token != null && token.trim().isNotEmpty) {
          return token.trim();
        }
      }

      await Future<void>.delayed(
        Duration(milliseconds: attempt < 3 ? 700 : 1400 + attempt * 650),
      );
      _throwIfPuzzleGenerationCancelled(shouldCancel);
    }

    throw StateError('Sign-in is still restoring. Please wait a moment.');
  }

  Future<String> _getReliableAppCheckToken({
    required bool forceRefresh,
    bool Function()? shouldCancel,
  }) async {
    for (var attempt = 0; attempt < 12; attempt += 1) {
      _throwIfPuzzleGenerationCancelled(shouldCancel);
      final token = await FirebaseAppCheck.instance.getToken(
        forceRefresh || attempt > 0,
      );
      _throwIfPuzzleGenerationCancelled(shouldCancel);
      if (token != null && token.trim().isNotEmpty) {
        return token.trim();
      }

      await Future<void>.delayed(
        Duration(milliseconds: attempt < 3 ? 700 : 1400 + attempt * 650),
      );
      _throwIfPuzzleGenerationCancelled(shouldCancel);
    }

    throw StateError(
      'App security verification is still preparing. Please wait a moment.',
    );
  }

  bool _shouldRetryRunpodProxyResponse({
    required int statusCode,
    required String message,
  }) {
    final normalized = message.toLowerCase();
    if (normalized.contains('today\'s puzzle generation limit') ||
        normalized.contains('another puzzle generation is already running') ||
        normalized.contains('please wait a moment before starting another puzzle')) {
      return false;
    }
    if (statusCode == 401) {
      return normalized.contains('appcheck') ||
          normalized.contains('app check') ||
          normalized.contains('firebase auth token') ||
          normalized.contains('signed in') ||
          normalized.contains('unauthorized');
    }

    return statusCode == 408 ||
        statusCode == 409 ||
        statusCode == 425 ||
        statusCode == 429 ||
        statusCode == 500 ||
        statusCode == 502 ||
        statusCode == 503 ||
        statusCode == 504 ||
        normalized.contains('comfyui server') ||
        normalized.contains('not reachable after multiple retries') ||
        normalized.contains('127.0.0.1:8188');
  }

  Map<String, dynamic> _buildRunpodWorkflow(
    String prompt,
    double difficulty,
    String solutionFileName,
  ) {
    final seed =
        DateTime.now().microsecondsSinceEpoch.remainder(1000000000000);
    return <String, dynamic>{
      '10': <String, dynamic>{
        'class_type': 'CheckpointLoaderSimple',
        'inputs': <String, dynamic>{
          'ckpt_name': 'Juggernaut-XL_v9_RunDiffusionPhoto_v2.safetensors',
        },
      },
      '11': <String, dynamic>{
        'class_type': 'CLIPTextEncode',
        'inputs': <String, dynamic>{'text': prompt, 'clip': ['10', 1]},
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
          'clip': ['10', 1],
        },
      },
      '16': <String, dynamic>{
        'class_type': 'ControlNetApplyAdvanced',
        'inputs': <String, dynamic>{
          'strength': 5.0 - ((((difficulty - 1.0) / 9.0).clamp(0.0, 1.0)) * 4.9),
          'start_percent': 0.0,
          'end_percent': 1.0,
          'positive': ['11', 0],
          'negative': ['15', 0],
          'control_net': ['14', 0],
          'image': ['17', 0],
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
          'seed': seed,
          'steps': 20,
          'cfg': 8,
          'sampler_name': 'euler',
          'scheduler': 'normal',
          'denoise': 1.0,
          'model': ['10', 0],
          'positive': ['16', 0],
          'negative': ['16', 1],
          'latent_image': ['19', 0],
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
        'inputs': <String, dynamic>{'samples': ['18', 0], 'vae': ['10', 2]},
      },
      '21': <String, dynamic>{
        'class_type': 'SaveImage',
        'inputs': <String, dynamic>{
          'filename_prefix': 'ComfyUI',
          'images': ['20', 0],
        },
      },
    };
  }

  String _extractGeneratedImage(Map<String, dynamic> statusData) {
    final output = statusData['output'];
    if (output is Map) {
      final images = output['images'];
      if (images is List && images.isNotEmpty && images.first is Map) {
        final first = Map<String, dynamic>.from(images.first as Map);
        return '${first['data'] ?? first['image'] ?? ''}'.trim();
      }
      final message = output['message'];
      if (message is String && message.trim().isNotEmpty) {
        return message.trim();
      }
    }

    if (output is List && output.isNotEmpty) {
      return '${output.first}'.trim();
    }

    return '';
  }

  String _extractGenerationError(Map<String, dynamic> statusData) {
    final directError = '${statusData['error'] ?? ''}'.trim();
    if (directError.isNotEmpty) {
      return directError;
    }

    final directMessage = '${statusData['errorMessage'] ?? statusData['message'] ?? ''}'.trim();
    if (directMessage.isNotEmpty) {
      return directMessage;
    }

    final output = statusData['output'];
    if (output is Map) {
      for (final key in ['error', 'message', 'stderr', 'detail']) {
        final value = '${output[key] ?? ''}'.trim();
        if (value.isNotEmpty) {
          return value;
        }
      }
    }

    return '';
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
}
