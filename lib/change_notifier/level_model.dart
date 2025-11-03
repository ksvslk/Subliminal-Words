import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:collection/collection.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:logging/logging.dart';
import 'package:operation_hermes/config/C.dart';
import 'package:operation_hermes/config/sounds.dart';
import 'package:operation_hermes/controller/ads_controller.dart';
import 'package:operation_hermes/controller/audio_controller.dart'
    show AudioController;
import 'package:operation_hermes/config/firebase_options.dart';
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
import 'package:path_provider/path_provider.dart';

class LevelModel with ChangeNotifier {
  final LevelPersistence persistence;
  final GamesServicesController? gamesServicesController;
  final AdsController? adsController;
  final MoneyController? inAppPurchaseController;
  final FirebaseService firebaseService;
  final ProgressPersistence progressPersistence;
  final AudioController? audioController;
  final SettingsPersistence settingsPersistence;
  final bool isOnline;

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
  bool isLevelReady = false; // New state to control content fade-in

  List<ProgressAchievement> progressAchievements = [];

  String? _pendingPackId;
  int? _pendingLevelNumber;

  LevelModel(
      {required this.adsController,
      required this.inAppPurchaseController,
      required this.gamesServicesController,
      required this.persistence,
      required this.progressPersistence,
      required this.audioController,
      required this.settingsPersistence,
      required this.firebaseService,
      required this.isOnline});

  Future<void> initialize() async {
    // On startup, we want to load the very first level of the initial pack.
    // First, create the models in a loading state.
    await _createModels(null);
    notifyListeners();

    SWLevel? initialLevelData;
    try {
      final initialPackId = 'first-look';
      // Request at least one level.
      final initialLevels =
          await firebaseService.getLevels(initialPackId, offline: !isOnline);
      if (initialLevels.isNotEmpty) {
        initialLevelData = initialLevels.first;
      } else {
        _log.warning(
            'No initial levels found from bundled assets or Firestore. Creating a placeholder level.');
        // Create a placeholder level if no actual level data is found.
        initialLevelData = SWLevel(
          id: 'placeholder__1',
          nr: 1,
          packId: initialPackId,
          name: 'No Levels Available',
          hintType: '', hints: {}, puzzlePath: '', puzzleThumbnailPath: '',
          solutionPath: '',
          tooltipStart:
              'No levels could be loaded. Please check your internet connection.',
          tooltipEnd: '', isEnabled: false,
          createdAt: DateTime.now(), modifiedAt: DateTime.now(),
          isBundled: true, // Treat as bundled to avoid network calls for assets
        );
      }
    } on FirebaseException catch (e) {
      _log.severe('Failed to fetch initial levels on startup.', e);
      // If Firebase fails, create a placeholder level with an error message.
      initialLevelData = SWLevel(
        id: 'error__1',
        nr: 1,
        packId: 'error',
        name: 'Error Loading Levels',
        hintType: '', hints: {}, puzzlePath: '', puzzleThumbnailPath: '',
        solutionPath: '',
        tooltipStart:
            'Could not load game data. Please check your internet connection and restart the app.',
        tooltipEnd: '', isEnabled: false,
        createdAt: DateTime.now(), modifiedAt: DateTime.now(),
        isBundled: true, // Treat as bundled
      );
    }

    // Now, load the determined initial level (either real or placeholder).
    if (initialLevelData != null) {
      await loadLevelFromSelection(initialLevelData);
    } else {
      // This case should ideally not be reached if initialLevelData is always set.
      _log.severe('Critical: initialLevelData is null after all attempts.');
      // Ensure loading indicators are turned off.
      networkRequestActive = false;
      isLevelReady = false;
      notifyListeners();
    }

    // Initialize online services regardless, if online.
    // This ensures ads, IAP, etc., can still function even if the first level failed to load.
    _initializeOnlineServices();
    await setupFCMListeners();
    _loadProgressAchievements();
    await _loadPendingLevel();
  }

  int get levelNr => currentLevel?.nr ?? -1;
  String get tooltipStart => currentLevel?.tooltipStart ?? "";
  String get tooltipEnd => currentLevel?.tooltipEnd ?? "";
  bool get isInitialTooltipDismissed => _initialTooltipDismissed;

  Future<void> _initializeOnlineServices() async {
    if (!isOnline) {
      _log.info('Device is offline. Skipping online service initialization.');
      return;
    }

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
      _log.warning('Progress achievements string from Remote Config is empty.');
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

  void _unlockAchievement() async {
    final achievementToUnlock = progressAchievements.firstWhereOrNull(
        (achievement) =>
            achievement.levelsToUnlock == currentLevel?.nr &&
            achievement.packId == currentLevel?.packId);

    if (achievementToUnlock == null) return;

    final isRangeOfLevelsCompleted =
        await progressPersistence.isRangeOfLevelsCompleted(
            1, achievementToUnlock.levelsToUnlock, achievementToUnlock.packId);

    if (isRangeOfLevelsCompleted) {
      _log.info("Unlocking achievement: ${achievementToUnlock.name}");
      gamesServicesController?.awardAchievement(
          iOS: achievementToUnlock.achievementIdAppstore,
          android: achievementToUnlock.achievementIdGoogleplay);
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

    // During initial creation with a null level, we don't need to notify.
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
    // Mark the initial tooltip as dismissed and clear any temporary tooltips.
    variousTooltip = "";
    _initialTooltipDismissed = true;
    notifyListeners();
  }

  Future<void> nextLevel() async {
    if (currentLevel == null) return;

    final nextLevelNr = levelNr + 1; // Calculate the next level number
    final String packId = currentLevel!.packId;
    SWLevel? nextLevelData;

    // If the current pack is a bundled pack, try to load the next level
    // from the local JSON first. This is much faster and works offline.
    if (FirebaseService.bundledPackAssets.containsKey(packId)) {
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

    // If the next level wasn't found in the bundle (or it's not a bundled pack),
    // fetch it from Firestore. This allows remote levels to work correctly.
    if (nextLevelData == null) {
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

    if (nextLevelData != null && nextLevelData.isEnabled) {
      // If the next level exists and is enabled, load it.
      await loadLevelFromSelection(nextLevelData);
    }
    // If there's no next level, you could navigate back to the level select screen
    // or show a "Pack Complete" message. For now, it does nothing.
  }

  void askForReview(int levelNr) async {
    if (levelNr == 15 || levelNr == 115) {
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
    // Immediately notify the UI that we are entering a loading state.
    networkRequestActive = true;
    isLevelReady = false; // Ensure new content is hidden before loading
    notifyListeners();

    // Introduce a small delay. This is the crucial step to prevent jank.
    // It gives the UI thread a moment to build and render the loading
    // indicator *before* we start the potentially blocking asset loading below.
    await Future.delayed(const Duration(milliseconds: 50));

    // Keep track of the old level in case loading fails.
    final oldLevel = currentLevel;

    try {
      await assignInitialLevelValues(selectedLevel, fromLevelSelect: true);
    } on FirebaseException catch (e) {
      _log.severe('Failed to load level from selection.', e);
      showMessageFromMascot(
          'Failed to load level. Please check your internet connection and try again.');
      // If loading fails, revert to the previous level to maintain a valid state.
      currentLevel = oldLevel;
      networkRequestActive = false;
      isLevelReady = false;
      notifyListeners();
    }
  }

  Future<void> assignInitialLevelValues(SWLevel level,
      {bool fromLevelSelect = false}) async {
    final minLoadingTime = Future.delayed(const Duration(milliseconds: 300));

    // Prepare for loading state
    isLevelReady = false;
    if (!fromLevelSelect) {
      networkRequestActive = true;
      notifyListeners();
    }
    _initialTooltipDismissed = false; // Reset dismissal flag for new level
    manipulationEnabled = false; // Reset on level load

    // PictureModel now handles its own asset path resolution (bundled vs. remote) and hint type logic
    // by receiving the full level object.
    await pictureModel.initializePicture(level: level);

    fieldModel.initializeLevel(level.name);

    final canLettersBeRemovedMore = fieldModel.isRemoveLettersAvailable();
    setLettersCanBeRemoved(canLettersBeRemovedMore);

    // Ensure the loading indicator was visible for a minimum amount of time
    // to prevent a jarring "flash" if loading is very fast.
    await minLoadingTime;

    // CRITICAL: Only assign the new level to currentLevel AFTER all async
    // operations have successfully completed.
    currentLevel = level;

    _log.info('assignInitialLevelValues: Saving last pack ID: ${level.packId}');
    await settingsPersistence.saveLastPackId(level.packId);
    // Step 1: Hide the loading indicator.
    levelCompleted = false;
    networkRequestActive = false;
    lettersAnimationFadeOutDuration = 1750;
    notifyListeners();

    // Step 2: A short delay before fading in the content makes the transition
    // feel more deliberate and less abrupt.
    await Future.delayed(const Duration(milliseconds: 50));
    isLevelReady = true;
    notifyListeners();
    if (levelNr >= 9) {
      showAds(levelNr);
    }
  }

  /// Navigates to the appropriate level selection screen.
  /// If a "last played pack" is stored, it navigates directly to that
  /// pack's level list. Otherwise, it navigates to the main categories screen.
  Future<void> navigateToLevelSelection(BuildContext context) async {
    _log.info(
        'navigateToLevelSelection: Attempting to navigate to level selection.');
    final lastPackId = await settingsPersistence.getLastPackId();
    _log.info('navigateToLevelSelection: Retrieved last pack ID: $lastPackId');

    if (lastPackId != null && lastPackId.isNotEmpty) {
      Pack? pack;
      _log.info(
          'navigateToLevelSelection: lastPackId is valid ($lastPackId). Attempting to get pack from Firebase.');

      // Try to fetch the full Pack object from Firebase.
      // This will use cache if available and network is disabled/offline.
      pack = await firebaseService.getPack(lastPackId);
      _log.info(
          'navigateToLevelSelection: FirebaseService.getPack returned: ${pack?.id ?? "null"}');

      if (pack == null) {
        // If the full Pack object couldn't be retrieved (e.g., offline and not in cache, or pack deleted),
        // create a minimal Pack object to still attempt navigation to the levels screen.
        // The levels screen will then try to load levels using this packId, potentially from cache/bundled.
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
        _log.info(
            'navigateToLevelSelection: Pack found. Navigating to /levels with pack: ${pack.id}');
        Navigator.of(context).pushNamed('/levels', arguments: pack);
        return;
      }
    }
    // If no pack is found or something goes wrong, default to the categories screen.
    if (context.mounted) {
      _log.info(
          'navigateToLevelSelection: No last pack found or pack not available. Navigating to /categories.');
      Navigator.of(context).pushNamed('/categories');
    }
  }

  void showAds(int levelWhereToShow) {
    if (inAppPurchaseController?.hasEntitlement(C.entitlementNoAdBreaksId) ==
        false) {
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
    _log.info('HighlightAction with $audioController');
    final availableLetters = fieldModel.getAvailableLetters();
    audioController?.playSfx(SfxType.rewardGiven);
    pictureModel.highlightLetter(availableLetters);
  }

  void showFactAction() {
    if (currentLevel == null || !currentLevel!.hasFactHint) {
      _log.warning(
          'showFactAction called for non-fact type level or no fact hint available.');
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
      // Start the picture model's completion process immediately.
      // This will swap the image path for 'fact' levels.
      pictureModel.setLevelComplete();

      // Use a delayed future to set the final win state for the rest of the UI.
      // This gives the PictureWidget time to receive the new image path and
      // start rendering the solution before other UI elements are removed.
      Future.delayed(const Duration(milliseconds: 50), () {
        levelCompleted = true;
        notifyListeners(); // Notify listeners to update UI for the completed state.
      });
      _saveProgress();
    }
    return win;
  }

  Future<void> _saveProgress() async {
    if (currentLevel != null) {
      await progressPersistence.saveCompletedLevel(
          currentLevel!.nr.toString(), currentLevel!.packId);
      _unlockAchievement();
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

    // This handles a tap on a notification when the app is TERMINATED
    RemoteMessage? initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) {
      _log.info("Handling initial notification message.");
      _handleNotificationTap(initialMessage);
    }

    // This handles a tap on a notification when the app is in the BACKGROUND
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    // This handles messages that arrive when the app is in the FOREGROUND
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
    _log.info("Notification tapped. Data: ${message.data}");
    final packId = message.data['packId'];
    final levelNumberString = message.data['levelNumber'];

    if (packId != null && levelNumberString != null) {
      final levelNumber = int.tryParse(levelNumberString);
      if (levelNumber != null) {
        _log.info("Setting pending level: Pack $packId, Level $levelNumber");
        _pendingPackId = packId;
        _pendingLevelNumber = levelNumber;
        _log.info(
            "Notification: _pendingPackId: $_pendingPackId, _pendingLevelNumber: $_pendingLevelNumber");
        _loadPendingLevel();
      } else {
        _log.warning(
            "Could not parse levelNumber from notification: $levelNumberString");
      }
    } else {
      _log.warning("Notification data is missing 'packId' or 'levelNumber'.");
    }
  }

  /// Checks if a level was requested from a notification and loads it.
  Future<void> _loadPendingLevel() async {
    if (_pendingPackId == null || _pendingLevelNumber == null) {
      return;
    }

    if (currentLevel == null) {
      _log.info(
          'Pending level detected, but model is not ready. Will retry after init.');
      return;
    }

    _log.info(
        'Model is ready. Loading pending level: Pack $_pendingPackId, Level $_pendingLevelNumber');

    try {
      final String packId = _pendingPackId!;
      final int levelNr = _pendingLevelNumber!;

      _log.info("Notification: pack Id: $packId, Level Nr: $levelNr");

      _pendingPackId = null;
      _pendingLevelNumber = null;

      final SWLevel? levelToLoad =
          await firebaseService.getLevel(packId, levelNr);

      _log.info("Notification: levelToLoad: $levelToLoad");

      if (levelToLoad != null && levelToLoad.isEnabled) {
        await loadLevelFromSelection(levelToLoad);
        _log.info('Successfully loaded level from notification.');
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
