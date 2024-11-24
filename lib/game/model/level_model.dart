import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection/collection.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:logging/logging.dart';
import 'package:operation_hermes/ads/ads_controller.dart';
import 'package:operation_hermes/competition/competition_controller.dart';
import 'package:operation_hermes/game/model/competition_data.dart';
import 'package:operation_hermes/game/model/field_model.dart';
import 'package:operation_hermes/game/level_data.dart';
import 'package:operation_hermes/game/model/picture_model.dart';
import 'package:operation_hermes/game/model/story_model.dart';
import 'package:operation_hermes/games_services/games_services.dart';
import 'package:operation_hermes/in_app_purchase/in_app_purchase_controller.dart';
import 'package:operation_hermes/level/persistence/level_persistence.dart';

class LevelModel with ChangeNotifier {
  final CompetitionController? competitionController;
  final LevelPersistence persistence;
  final GamesServicesController? gamesServicesController;
  final AdsController? adsController;
  final InAppPurchaseController? inAppPurchaseController;
  ValueNotifier<AppLifecycleState>? _lifecycleNotifier;

  static final _log = Logger('LevelModel');

  int levelNr = -1;
  String tooltipStart = "";
  String tooltipEnd = "";
  String variousTooltip = "";
  bool levelCompleted = false;
  bool unlocked = false;
  late PictureModel pictureModel;
  late FieldModel fieldModel;
  late StoryModel storyModel;
  CompetitionData? competitionData;
  FirebaseAnalytics analytics = FirebaseAnalytics.instance;

  bool remove3Available = false;
  bool manipulationEnabled = false;

  bool remove3NotificationSeen = false;
  bool manipulatetNotificationSeen = false;
  bool higlightNotificationSeen = false;

  final lettersAnimationFadeInDuration = 1750;
  var lettersAnimationFadeOutDuration = 1750;

  ValueNotifier<int> currentStoryCardPageNr1 = ValueNotifier(1);
  ValueNotifier<int> currentStoryCardPageNr2 = ValueNotifier(1);
  ValueNotifier<int> currentStoryCardPageNr3 = ValueNotifier(1);

  int currentStoryCardPack = 1;

  bool networkRequestActive = false;

  LevelModel(
      {required this.competitionController,
      required this.adsController,
      required this.inAppPurchaseController,
      required this.gamesServicesController,
      required this.persistence});

  Future<void> initialize() async {
    final latestLevelData = await persistence.initialize().then((value) async {
      return await persistence.getLatestLevelData();
    });
    final level = LevelData.from(latestLevelData);
    final previousStory = await persistence.initialize().then((value) async {
      return await persistence.getLastLevelWordAndStory(level.nr - 1);
    });
    await _createModels(level, previousStory);
    gamesServicesController?.signedIn
        .then((value) => updateProgressFromCloud());

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.notification != null) {
        showMessageFromMascot(
            "${message.notification?.title}. ${message.notification?.body}.");
      }
    });
  }

  Future<void> updateProgressFromCloud() async {
    final cloudGameData = await gamesServicesController?.loadGame();
    final localMaxLevelNr = await persistence.getMaxLevelNrUnlocked();

    if (cloudGameData?.progress.compareTo(levelNr) == 1 ||
        cloudGameData?.progress.compareTo(levelNr) == 0) {
      unlocked = true;
    }

    // When cloud progress is higher then save
    if (cloudGameData?.progress.compareTo(localMaxLevelNr) == 1) {
      _log.log(Level.INFO,
          'Cloud is more powerful, unlock levels until: ${cloudGameData?.progress}');
      await persistence.unlockLevelsUntil(cloudGameData!.progress);
      variousTooltip =
          "Restored from cloud. Latest level accessible through story bar.";
      notifyListeners();
    } else {
      final lastLevelData = await persistence.getLatestLevelData();
      final lastLevelNr = int.tryParse(lastLevelData.$1);
      if (lastLevelNr != null && levelNr != lastLevelNr) {
        loadLevel(lastLevelNr);
      }
    }
  }

  void showMessageFromMascot(String message) {
    variousTooltip = message;
    notifyListeners();
  }

  int _getCurrentStoryCardPack() {
    if (levelNr <= 100) {
      return 1;
    } else if (levelNr > 100 && levelNr <= 200) {
      return 2;
    } else {
      return 3;
    }
  }

  Future<void> _createModels(
      LevelData level, (String, String)? previousStory) async {
    levelNr = level.nr;
    currentStoryCardPack = _getCurrentStoryCardPack();
    tooltipStart = level.tooltipStart;
    tooltipEnd = level.tooltipEnd;
    if (tooltipStart.isEmpty) {
      tooltipStart =
          "Welcome back, I hope you've been well since our last session.";
    }

    storyModel = StoryModel();
    storyModel.previousWordAndStory =
        previousStory ?? ("", "Let the story unfold...");
    storyModel.currentWordAndStory = (level.word, level.story);
    storyModel.addNextStory(storyModel.previousWordAndStory);

    manipulationEnabled = level.manipulationEnabled;

    pictureModel = PictureModel(
        scale: 1.0,
        quarterTurn: 0,
        picturePath: level.picturePath,
        svgPath: level.svgPath,
        levelNr: level.nr)
      ..initializePicture(level);

    fieldModel = FieldModel(level: level);

    final canLettersBeRemovedMore = fieldModel.isRemoveLettersAvailable();
    setLettersCanBeRemoved(canLettersBeRemovedMore);
    unlocked = level.unlocked;
    if (level.levelCompleted) _setLevelCompleted();
  }

  void setLettersCanBeRemoved(bool newValue) {
    remove3Available = newValue;
    notifyListeners();
  }

  void hideAllPossibleTooltips() {
    tooltipEnd = "";
    tooltipStart = "";
    variousTooltip = "";
    notifyListeners();
  }

  int getStoryPackNr() {
    if (levelNr + 1 > 200) {
      return 3;
    } else if (levelNr + 1 > 100) {
      return 2;
    } else {
      return 1;
    }
  }

  Future<void> nextLevel() async {
    lettersAnimationFadeOutDuration = 0;
    currentStoryCardPack = getStoryPackNr();
    notifyListeners();
    final nextLevelNr = levelNr + 1;
    if (currentStoryCardPack == 3) {
      final lastLevel = await persistence.getMaxLevelInPersistence();
      if (lastLevel == levelNr) {
        variousTooltip =
            "Cool! You will receive a message when next level is out - keep your push notifications on!";
        notifyListeners();
      } else {
        await loadLevel(nextLevelNr);
        askForReview(nextLevelNr);
      }
    } else {
      await loadLevel(nextLevelNr);
      askForReview(nextLevelNr);
    }
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

  Future<void> loadLevel(int nr, {bool fromLevelSelect = false}) async {
    _log.log(Level.INFO, "loadLevel");
    persistence.getLevelNr(nr).then((currentLevel) {
      final level = LevelData.from(currentLevel);
      persistence
          .getLastLevelWordAndStory(nr - 1)
          .then((prevLevelWordAndStory) {
        assignInitialLevelValues(level, prevLevelWordAndStory,
            fromLevelSelect: fromLevelSelect);
      }).onError((error, stackTrace) {
        _log.severe("Error getting the story for level ${nr - 1}", error);
      });
    }).onError((error, stackTrace) {
      _log.severe("Could not load the level nr: $nr", error);
    });
  }

  Future<void> assignInitialLevelValues(
      LevelData level, (String, String)? previousStory,
      {bool fromLevelSelect = false}) async {
    // LevelModel
    levelNr = level.nr;
    tooltipStart = level.tooltipStart;
    tooltipEnd = level.tooltipEnd;
    manipulationEnabled = level.manipulationEnabled;

    storyModel.previousWordAndStory =
        previousStory ?? ("", "Let the story unfold...");
    storyModel.currentWordAndStory = (level.word, level.story);
    if (fromLevelSelect) storyModel.clearAndAddStory();

    // PictureModel
    await pictureModel.initializePicture(level);

    // FieldModel
    fieldModel.initializeLevel(level);

    final canLettersBeRemovedMore = fieldModel.isRemoveLettersAvailable();
    setLettersCanBeRemoved(canLettersBeRemovedMore);
    levelCompleted = false;
    unlocked = level.unlocked;
    lettersAnimationFadeOutDuration = 1750;
    notifyListeners();
    if (levelNr >= 19) {
      loadAds(
          levelNr + 1); // should execute be always 1 level before showing ads
      showAds(levelNr);
    }
  }

  void loadAds(int levelBeforeShowing) {
    if (levelBeforeShowing % 5 == 0 &&
        inAppPurchaseController?.isNoAdsPurchased() == false) {
      adsController?.loadInterstitialAd(null);
    }
  }

  void showAds(int levelWhereToShow) {
    if (levelWhereToShow % 5 == 0 &&
        inAppPurchaseController?.isNoAdsPurchased() == false) {
      adsController?.showInterstitialAd();
    }
  }

  Future<int> getMaxLevelNr() async {
    return persistence.getMaxLevelNrUnlocked();
  }

  Future<int> getLastLevelNr() async {
    if (currentStoryCardPack == 1) {
      return 100;
    } else if (currentStoryCardPack == 2) {
      return 200;
    } else {
      return persistence.getMaxLevelInPersistence();
    }
  }

  Future<(List<LevelData>, int)> getCurrentStoryLevelsAndContinueLevel() async {
    final levels = await persistence.getAllLevelsForPack(currentStoryCardPack);
    int lastLevelNrInPersistence = await getLastLevelNr();
    final lastUnlockedLevelNr = (levels
        .lastWhereOrNull((element) =>
            element.unlocked == true && element.nr < lastLevelNrInPersistence)
        ?.nr);

    int lastContinueLevelNr = lastUnlockedLevelNr == null
        ? getDefaultFirstLevel()
        : lastUnlockedLevelNr + 1;

    _log.log(Level.INFO, "Levels: ${levels.last.nr}");
    return (levels, lastContinueLevelNr);
  }

  int getDefaultFirstLevel() {
    if (currentStoryCardPack == 1) {
      return 1;
    } else if (currentStoryCardPack == 2) {
      return 101;
    } else {
      return 201;
    }
  }

  void changeStoryPackNr(int newPackNr) {
    if (newPackNr == 3) {
      networkRequestActive = true;
      currentStoryCardPack = newPackNr;
      notifyListeners();
      syncLevelsWithCloud().then((str) {
        variousTooltip = str;
        networkRequestActive = false;
        notifyListeners();
      }).onError((error, stackTrace) {
        variousTooltip =
            "Something went terribly wrong when trying to update levels. ${error}";
        currentStoryCardPack = newPackNr;
        networkRequestActive = false;
        notifyListeners();
      });
    } else {
      currentStoryCardPack = newPackNr;
      notifyListeners();
    }
  }

  Future<String> syncLevelsWithCloud() async {
    final maxLocalLevel = await getMaxLevelNr();
    final _firestore = FirebaseFirestore.instance;
    try {
      final levels = await _firestore.collection("endless").doc("levels").get();
      final maxCloudLevel = levels.data()?["max_level"] as int?;
      await Future.delayed(const Duration(seconds: 5));
      return "Local level is $maxLocalLevel and cloud level is $maxCloudLevel";
    } catch (error) {
      rethrow;
    }
  }

  void _setLevelCompleted() {
    levelCompleted = true;
    fieldModel.setLevelCompleted();
    pictureModel.setLevelComplete();
    notifyListeners();
  }

  // Actions
  void remove3Action() {
    fieldModel.remove3ArbitaryLetters();
    final canLettersBeRemovedMore = fieldModel.isRemoveLettersAvailable();
    setLettersCanBeRemoved(canLettersBeRemovedMore);
  }

  void highlightAction() {
    pictureModel.highlightLetter();
  }

  void manipulationAction() {
    manipulationEnabled = true;
    notifyListeners();
  }

  bool checkForWin() {
    var win = fieldModel.checkForWin();
    levelCompleted = win;
    unlocked = win;
    if (win) {
      _save();
      storyModel.addNextStory(storyModel.currentWordAndStory);
      pictureModel.setLevelComplete();
      checkForCompetitionWin();
      logLevelEnd();
    }
    notifyListeners();
    return win;
  }

  void checkForCompetitionWin() {
    _log.info("checkForCompetitionWin");
    if (levelNr == CompetitionController.competitionGoalLevel) {
      competitionController?.getCompetitionData().then((r) {
        if (r?.finished == false) {
          competitionController?.updatePlayerLevel(levelNr).then((result) {
            if (result?.finished == true && result?.promoCode != "") {
              competitionData = result;
              notifyListeners();
            }
          });
        }
      });
    }
  }

  Future<void> logLevelEnd() async {
    if ([
      1,
      3,
      10,
      20,
      30,
      40,
      50,
      60,
      70,
      80,
      90,
      100,
      110,
      120,
      130,
      140,
      150,
      175,
      200
    ].contains(levelNr)) {
      await analytics.logLevelEnd(
        levelName: levelNr.toString(),
      );
    }
  }

  LevelData getLevelData() {
    return LevelData(
        levelNr,
        fieldModel.word,
        storyModel.currentWordAndStory.$2,
        pictureModel.picturePath,
        pictureModel.svgPath,
        tooltipStart,
        tooltipEnd,
        manipulationEnabled,
        levelCompleted,
        fieldModel.disabledLettersCount,
        unlocked);
  }

  Future<void> _save() async {
    // Local save
    final level = getLevelData();
    if (level.levelCompleted) {
      level.disabledLettersCount = 0;
      level.manipulationEnabled = false;
    }
    final persistentData = level.getLevelDataBasic();
    persistence.setLevelData(persistentData);
    persistence.setLatestLevel(levelNr);

    // Possible cloud save
    final localMaxLevelNr = await persistence.getMaxLevelNrUnlocked();
    gamesServicesController?.saveGame(localMaxLevelNr);
  }

  ValueNotifier<int> getCurrentStoryValueNotifier() {
    if (currentStoryCardPack == 1) {
      return currentStoryCardPageNr1;
    } else if (currentStoryCardPack == 2) {
      return currentStoryCardPageNr2;
    } else {
      return currentStoryCardPageNr3;
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
