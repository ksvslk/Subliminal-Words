import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:logging/logging.dart';
import 'package:operation_hermes/config/C.dart';
import 'package:operation_hermes/config/sounds.dart';
import 'package:operation_hermes/controller/ads_controller.dart';
import 'package:operation_hermes/controller/audio_controller.dart'
    show AudioController;
import 'package:operation_hermes/change_notifier/field_model.dart';
import 'package:operation_hermes/controller/firebase_service.dart';
import 'package:operation_hermes/change_notifier/picture_model.dart';
import 'package:operation_hermes/controller/games_services.dart';
import 'package:operation_hermes/controller/money_controller.dart';
import 'package:operation_hermes/data/pack.dart';
import 'package:operation_hermes/data/progress_achievement.dart';
import 'package:operation_hermes/persistence/level_persistence.dart';
import 'package:operation_hermes/persistence/progress_persistence.dart';
import 'package:operation_hermes/persistence/settings_persistence.dart';
import 'package:operation_hermes/data/sw_level.dart';

class LevelModel with ChangeNotifier {
  final LevelPersistence persistence;
  final GamesServicesController? gamesServicesController;
  final AdsController? adsController;
  final MoneyController? inAppPurchaseController;
  final FirebaseService firebaseService;
  final ProgressPersistence progressPersistence;
  final AudioController? audioController;
  final SettingsPersistence settingsPersistence;

  ValueNotifier<AppLifecycleState>? _lifecycleNotifier;

  static final _log = Logger('LevelModel');

  SWLevel? currentLevel;
  bool _initialTooltipDismissed = false;

  String variousTooltip = "";
  bool levelCompleted = false;
  late PictureModel pictureModel;
  late FieldModel fieldModel;
  FirebaseAnalytics analytics = FirebaseAnalytics.instance;

  bool remove3Available = false;
  bool manipulationEnabled = false;

  bool remove3NotificationSeen = false;
  bool manipulatetNotificationSeen = false;
  bool higlightNotificationSeen = false;

  final lettersAnimationFadeInDuration = 1750;
  var lettersAnimationFadeOutDuration = 1750;

  bool networkRequestActive = false;
  bool isLevelReady = false;

  List<ProgressAchievement> progressAchievements = [];

  String? _pendingPackId;
  int? _pendingLevelNumber;

  DateTime? _levelStartTime;

  LevelModel(
      {required this.adsController,
      required this.inAppPurchaseController,
      required this.gamesServicesController,
      required this.persistence,
      required this.progressPersistence,
      required this.audioController,
      required this.settingsPersistence,
      required this.firebaseService});

  Future<void> initialize() async {
    await _createModels(null);
    notifyListeners();

    SWLevel? initialLevelData;
    try {
      final initialPackId = 'first-look';
      final initialLevels = await firebaseService.getLevels(initialPackId);
      if (initialLevels.isNotEmpty) {
        initialLevelData = initialLevels.first;
      } else {
        _log.warning(
            'No initial levels found from bundled assets or Firestore. Creating a placeholder level.');
        initialLevelData = SWLevel(
          id: 'placeholder__1',
          documentId: 'placeholder__1',
          nr: 1,
          packId: initialPackId,
          name: 'No Levels Available',
          hintType: '',
          hints: {},
          puzzlePath: '',
          puzzleThumbnailPath: '',
          solutionPath: '',
          tooltipStart: 'No levels could be loaded.',
          tooltipEnd: '',
          isEnabled: false,
          createdAt: DateTime.now(),
          modifiedAt: DateTime.now(),
          isBundled: true,
        );
      }
    } on FirebaseException catch (e) {
      _log.severe('Failed to fetch initial levels on startup.', e);
      initialLevelData = SWLevel(
        id: 'error__1',
        documentId: 'error__1',
        nr: 1,
        packId: 'error',
        name: 'Error Loading Levels',
        hintType: '',
        hints: {},
        puzzlePath: '',
        puzzleThumbnailPath: '',
        solutionPath: '',
        tooltipStart: 'Could not load game data.',
        tooltipEnd: '',
        isEnabled: false,
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
        isBundled: true,
      );
    }

    await loadLevelFromSelection(initialLevelData);
    await _initializeOnlineServices();
    await setupFCMListeners();
    await _loadPendingLevel();
    _loadProgressAchievements();
  }

  int get levelNr => currentLevel?.nr ?? -1;
  String get tooltipStart => currentLevel?.tooltipStart ?? "";
  String get tooltipEnd => currentLevel?.tooltipEnd ?? "";
  bool get isInitialTooltipDismissed => _initialTooltipDismissed;

  Future<void> _initializeOnlineServices() async {
    _log.info('Device is online. Initializing online services...');
    adsController?.requestTheLatestConsentInformation();
    gamesServicesController?.initialize();
    gamesServicesController?.signedIn.then((_) => updateProgressFromCloud());
  }

  Future<void> updateProgressFromCloud() async {
    final cloudGameData = await gamesServicesController?.loadGame();
    progressPersistence.saveLoadedLevels(cloudGameData);
  }

  void showMessageFromMascot(String message) {
    variousTooltip = message;
    notifyListeners();
  }

  void _loadProgressAchievements() {
    final jsonString =
        FirebaseRemoteConfig.instance.getString(C.progressAchievemetns);
    if (jsonString.isEmpty) {
      return;
    }
    try {
      final jsonList = jsonDecode(jsonString) as List<dynamic>;
      progressAchievements =
          jsonList.map((e) => ProgressAchievement.fromMap(e)).toList();
    } catch (e, st) {
      _log.severe(
          'Failed to parse progress achievements from Remote Config.', e, st);
    }
  }

  void _tryUnlockingAchievements() async {
    final achievementsToUnlock = progressAchievements
        .where((achievement) => achievement.packId == currentLevel?.packId);
    if (achievementsToUnlock.isEmpty) return;

    for (final a in achievementsToUnlock) {
      final isRangeOfLevelsCompleted = await progressPersistence
          .isRangeOfLevelsCompleted(1, a.levelsToUnlock, a.packId);
      if (isRangeOfLevelsCompleted) {
        _log.info("Unlocking achievement: ${a.name}");
        gamesServicesController?.awardAchievement(
            iOS: a.achievementIdAppstore, android: a.achievementIdGoogleplay);
      }
    }
  }

  Future<void> _createModels(SWLevel? level) async {
    currentLevel = level;
    manipulationEnabled = false; // Will be set on level load

    pictureModel = PictureModel(
        scale: 1.0,
        quarterTurn: 0,
        picturePath: "",
        svgPath: "",
        levelNr: -1,
        firebaseService: firebaseService); // Pass firebaseService here

    fieldModel = FieldModel(levelWord: "");

    if (level != null) {
      await assignInitialLevelValues(level);
    }

    if (level != null) {
      final canLettersBeRemovedMore = fieldModel.isRemoveLettersAvailable();
      setLettersCanBeRemoved(canLettersBeRemovedMore);
    }
  }

  void setLettersCanBeRemoved(bool newValue) {
    if (remove3Available == newValue) return;
    remove3Available = newValue;
    notifyListeners();
  }

  void hideAllPossibleTooltips() {
    variousTooltip = "";
    _initialTooltipDismissed = true;
    notifyListeners();
  }

  Future<void> nextLevel() async {
    if (currentLevel == null) return;

    final nextLevelNr = levelNr + 1;
    final String packId = currentLevel!.packId;
    SWLevel? nextLevelData;

    if (currentLevel!.isCreatorOwned) {
      nextLevelData = await firebaseService.getMyLevelByNumber(nextLevelNr);
    }

    if (nextLevelData == null &&
        FirebaseService.bundledPackAssets.containsKey(packId)) {
      try {
        final String jsonString = await rootBundle
            .loadString(FirebaseService.bundledPackAssets[packId]!);
        final List<dynamic> jsonList = json.decode(jsonString);
        final nextLevelJson = jsonList.firstWhere(
            (level) => level['nr'] == nextLevelNr,
            orElse: () => null);
        if (nextLevelJson != null) {
          nextLevelData = SWLevel.fromJson(packId, nextLevelJson);
        }
      } catch (e) {
        _log.warning('Could not load next bundled level from JSON', e);
      }
    }

    if (nextLevelData == null && !currentLevel!.isCreatorOwned) {
      try {
        nextLevelData = await firebaseService.getLevel(packId, nextLevelNr);
      } on FirebaseException catch (e) {
        _log.severe('Failed to fetch next level from Firestore.', e);
        showMessageFromMascot(
            'Could not load the next level. Please check your internet connection.');
        networkRequestActive = false;
        notifyListeners();
        return;
      }
    }

    // This means that no next level was found in the pack
    if (nextLevelData?.nr == -1 && variousTooltip.isEmpty) {
      showMessageFromMascot(
          'Level Select is ⇡ above. This was the last level of "${nextLevelData?.packNameSanitized}"!');
      notifyListeners();
      return;
    } else if (nextLevelData?.nr == -1) {
      hideAllPossibleTooltips();
      return;
    }

    if (nextLevelData != null && nextLevelData.isEnabled) {
      await loadLevelFromSelection(nextLevelData);
    }
  }

  void askForReview(int levelNr) async {
    if (levelNr == 15) {
      final InAppReview inAppReview = InAppReview.instance;
      if (await inAppReview.isAvailable()) {
        try {
          inAppReview.requestReview();
        } on Exception catch (e) {
          _log.log(Level.SEVERE,
              "Something went wrong when trying to request review.", e);
        }
      }
    }
  }

  Future<void> loadLevelFromSelection(SWLevel selectedLevel) async {
    networkRequestActive = true;
    isLevelReady = false;
    notifyListeners();

    await Future.delayed(const Duration(milliseconds: 50));
    final oldLevel = currentLevel;

    try {
      await assignInitialLevelValues(selectedLevel, fromLevelSelect: true);
    } on FirebaseException catch (e) {
      _log.severe('Failed to load level from selection.', e);
      showMessageFromMascot(
          'Failed to load level. Please check your internet connection and try again.');
      currentLevel = oldLevel;
      networkRequestActive = false;
      isLevelReady = false;
      notifyListeners();
    }
  }

  Future<void> assignInitialLevelValues(SWLevel level,
      {bool fromLevelSelect = false}) async {
    final minLoadingTime = Future.delayed(const Duration(milliseconds: 300));

    isLevelReady = false;
    if (!fromLevelSelect) {
      networkRequestActive = true;
      notifyListeners();
    }
    _initialTooltipDismissed = false;
    manipulationEnabled = false;
    await pictureModel.initializePicture(level: level);
    fieldModel.initializeLevel(level.name);
    final canLettersBeRemovedMore = fieldModel.isRemoveLettersAvailable();
    setLettersCanBeRemoved(canLettersBeRemovedMore);
    await minLoadingTime;
    currentLevel = level;
    await settingsPersistence.saveLastPackId(level.packId);
    levelCompleted = false;
    networkRequestActive = false;
    lettersAnimationFadeOutDuration = 1750;
    notifyListeners();
    final adsDisplayLevelLimit =
        FirebaseRemoteConfig.instance.getInt(C.adsDisplayLevelLimit);
    await Future.delayed(const Duration(milliseconds: 50));
    isLevelReady = true;

    _levelStartTime = DateTime.now();
    await trackLevelBegin(level.nr, level.packId);

    notifyListeners();
    if (levelNr >= adsDisplayLevelLimit) {
      showAds(levelNr);
    }
  }

  Future<void> navigateToLevelSelection(BuildContext context) async {
    final lastPackId = await settingsPersistence.getLastPackId();
    if (lastPackId != null && lastPackId.isNotEmpty) {
      Pack? pack;
      pack = await firebaseService.getPack(lastPackId);
      if (pack == null) {
        _log.warning(
            'navigateToLevelSelection: Could not retrieve full Pack object for ID: $lastPackId. Creating a placeholder Pack.');
        pack = Pack(
          id: lastPackId,
          name: 'Last Played Pack', // Generic name
          categoryId: '', // Placeholder
          order: 0, // Placeholder
          description: 'Could not load pack details.', // Default description
          thumbnailUrl: '', // Default to empty string
          lastUpdated: DateTime.now(), // Default to current time
          totalLevels: 100, // Assume a reasonable default for UI display
        );
      }

      if (context.mounted) {
        Navigator.of(context).pushNamed('/levels', arguments: pack);
        return;
      }
    }
    if (context.mounted) {
      Navigator.of(context).pushNamed('/categories');
    }
  }

  void showAds(int levelWhereToShow) {
    if (inAppPurchaseController?.hasEntitlement(C.entitlementNoAdBreaksId) ==
            false &&
        inAppPurchaseController?.hasAllAccess() == false) {
      adsController?.showInterstitialAd();
    }
  }

  void remove3Action() {
    fieldModel.remove3ArbitaryLetters();
    final canLettersBeRemovedMore = fieldModel.isRemoveLettersAvailable();
    audioController?.playSfx(SfxType.wrong);
    setLettersCanBeRemoved(canLettersBeRemovedMore);
  }

  void highlightAction() {
    final availableLetters = fieldModel.getAvailableLetters();
    audioController?.playSfx(SfxType.rewardGiven);
    pictureModel.highlightLetter(availableLetters);
  }

  void showFactAction() {
    if (currentLevel == null || !currentLevel!.hasFactHint) {
      audioController?.playSfx(SfxType.notAllowed);
      return;
    }
    variousTooltip = currentLevel!.factHint!;
    audioController?.playSfx(SfxType.rewardGiven);
    notifyListeners();
  }

  void manipulationAction() {
    manipulationEnabled = true;
    audioController?.playSfx(SfxType.rewardGiven);
    notifyListeners();
  }

  bool checkForWin() {
    var win = fieldModel.checkForWin();
    if (win) {
      int timeTakenSeconds = 0;
      if (_levelStartTime != null) {
        timeTakenSeconds =
            DateTime.now().difference(_levelStartTime!).inSeconds;
      }
      trackLevelFinish(
          currentLevel?.nr, currentLevel?.packId, timeTakenSeconds);
      pictureModel.setLevelComplete();
      Future.delayed(const Duration(milliseconds: 50), () {
        levelCompleted = true;
        notifyListeners();
      });
      _saveProgress();
    }
    return win;
  }

  Future<void> trackLevelBegin(int? levelNumber, String? packName) async {
    if (levelNumber == null || packName == null) return;
    await FirebaseAnalytics.instance.logEvent(
      name: 'level_begin', // Standard event name
      parameters: {
        'level_number': levelNumber.toString(), // Make sure this is an Integer
        'pack_name': packName,
        // Create a composite ID for easier reading in basic reports
        'level_id': '${packName}_$levelNumber',
      },
    );
  }

  Future<void> trackLevelFinish(
      int? levelNumber, String? packName, int timeTaken) async {
    if (levelNumber == null || packName == null) return;
    await FirebaseAnalytics.instance.logEvent(
      name: 'level_finish',
      parameters: {
        'level_number': levelNumber.toString(),
        'pack_name': packName,
        'time_taken': timeTaken,
        'level_id': '${packName}_$levelNumber',
      },
    );
  }

  Future<void> _saveProgress() async {
    if (currentLevel != null) {
      await progressPersistence.saveCompletedLevel(
          currentLevel!.nr.toString(), currentLevel!.packId);
      _tryUnlockingAchievements();
      final completedLevels = await progressPersistence.getCompletedLevels();
      gamesServicesController?.saveGame(completedLevels);
      notifyListeners();
    }
  }

  Future<int> getCompletedLevelsCountForCategory(String categoryId) async {
    final packsInCategory = await firebaseService.getPacks(categoryId);
    final packIds = packsInCategory.map((pack) => pack.id).toList();
    return await progressPersistence
        .getCompletedLevelsCountForCategory(packIds);
  }

  Future<int> getCompletedLevelsCountForPack(String packId) async {
    return await progressPersistence.getCompletedLevelsCountForPack(packId);
  }

  Future<int> getUnlockedLevelsCountForCategory(String categoryId) =>
      getCompletedLevelsCountForCategory(categoryId);

  Future<int> getUnlockedLevelsCountForPack(String packId) =>
      getCompletedLevelsCountForPack(packId);

  Future<void> setupFCMListeners() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    await messaging.requestPermission();

    RemoteMessage? initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationTap(initialMessage);
    }
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      try {
        final packName = message.data['packId']
            .toString()
            .split('-')
            .map((word) => word[0].toUpperCase() + word.substring(1))
            .join(' ');
        final levelNumber = message.data['levelNumber'].toString();
        showMessageFromMascot('Level $levelNumber added to "$packName"');
      } catch (e) {
        showMessageFromMascot('New level added!');
      }
    });
    await messaging.subscribeToTopic('sw_plus_levels');
  }

  void _handleNotificationTap(RemoteMessage message) {
    final packId = message.data['packId'];
    final levelNumberString = message.data['levelNumber'];

    if (packId != null && levelNumberString != null) {
      final levelNumber = int.tryParse(levelNumberString);
      if (levelNumber != null) {
        _pendingPackId = packId;
        _pendingLevelNumber = levelNumber;
        _loadPendingLevel();
      } else {
        _log.warning(
            "Could not parse levelNumber from notification: $levelNumberString");
      }
    } else {
      _log.warning("Notification data is missing 'packId' or 'levelNumber'.");
    }
  }

  Future<void> _loadPendingLevel() async {
    if (_pendingPackId == null || _pendingLevelNumber == null) {
      return;
    }
    if (currentLevel == null) {
      return;
    }

    try {
      final String packId = _pendingPackId!;
      final int levelNr = _pendingLevelNumber!;

      _pendingPackId = null;
      _pendingLevelNumber = null;

      final SWLevel? levelToLoad =
          await firebaseService.getLevel(packId, levelNr);

      if (levelToLoad != null && levelToLoad.isEnabled) {
        await loadLevelFromSelection(levelToLoad);
      } else {
        _log.warning('Could not load pending level. Not found or not enabled.');
        showMessageFromMascot('Could not load the requested level.');
      }
    } catch (e, st) {
      _log.severe('Error loading pending level from notification', e, st);
      showMessageFromMascot('An error occurred loading the level.');
    }
  }

  void attachLifecycleNotifier(
      ValueNotifier<AppLifecycleState> lifecycleNotifier) {
    _lifecycleNotifier?.removeListener(_handleAppLifecycle);
    lifecycleNotifier.addListener(_handleAppLifecycle);
    _lifecycleNotifier = lifecycleNotifier;
  }

  void _handleAppLifecycle() {
    switch (_lifecycleNotifier!.value) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
      case AppLifecycleState.resumed:
      case AppLifecycleState.inactive:
        break;
    }
  }

  @override
  void dispose() {
    super.dispose();
    _lifecycleNotifier?.removeListener(_handleAppLifecycle);
  }
}
