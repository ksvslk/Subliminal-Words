import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection/collection.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:logging/logging.dart';
import 'package:operation_hermes/controller/ads_controller.dart';
import 'package:operation_hermes/controller/competition_controller.dart';
import 'package:operation_hermes/config/firebase_options.dart';
import 'package:operation_hermes/change_notifier/competition_data.dart';
import 'package:operation_hermes/change_notifier/field_model.dart';
import 'package:operation_hermes/data/level_data.dart';
import 'package:operation_hermes/change_notifier/picture_model.dart';
import 'package:operation_hermes/controller/games_services.dart';
import 'package:operation_hermes/controller/in_app_purchase_controller.dart';
import 'package:operation_hermes/persistence/level_persistence.dart';
import 'package:operation_hermes/data/level.dart' as LsLevel;
import 'package:path_provider/path_provider.dart';

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
  CompetitionData? competitionData;
  FirebaseAnalytics analytics = FirebaseAnalytics.instance;

  bool remove3Available = false;
  bool manipulationEnabled = false;

  bool remove3NotificationSeen = false;
  bool manipulatetNotificationSeen = false;
  bool higlightNotificationSeen = false;

  final lettersAnimationFadeInDuration = 1750;
  var lettersAnimationFadeOutDuration = 1750;

  bool openQuestTab = false;
  bool networkRequestActive = false;

  LevelModel(
      {required this.competitionController,
      required this.adsController,
      required this.inAppPurchaseController,
      required this.gamesServicesController,
      required this.persistence});


  Future<void> initialize() async {
    /*
    final latestLevelData = await persistence.initialize().then((value) async {
      return await persistence.getLatestLevelData();
    });
    final level = LevelData.from(latestLevelData);
    await _createModels(level);
    gamesServicesController?.signedIn
        .then((value) => updateProgressFromCloud());


    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      variousTooltip = "New level added to the 'Quest' chapter!";
      notifyListeners();
    });
    */

  }

  Future<void> updateProgressFromCloud() async {
    /*
    final cloudGameData = await gamesServicesController?.loadGame();
    final localMaxLevelNr =
        await persistence.getMaxLeveNrUnlockedInRange(1, 200);
    final localMaxLevelNrForQuest = await persistence.getMaxLevelNrUnlocked();

    if (cloudGameData?.progress.compareTo(levelNr) == 1 ||
        cloudGameData?.progress.compareTo(levelNr) == 0 ||
        cloudGameData?.questProgress?.compareTo(levelNr) == 1 ||
        cloudGameData?.questProgress?.compareTo(levelNr) == 0) {
      unlocked = true;
    }

    var cloudRestore = false;

    if (cloudGameData?.questProgress?.compareTo(localMaxLevelNrForQuest) == 1) {
      await persistence.unlockLevelsRange(201, cloudGameData!.questProgress!);
      cloudRestore = true;
    }

    if (cloudGameData?.progress.compareTo(localMaxLevelNr) == 1) {
      await persistence.unlockLevelsRange(1, cloudGameData!.progress);
      cloudRestore = true;
    }

    if (!cloudRestore) {
      final lastLevelData = await persistence.getLatestLevelData();
      final lastLevelNr = int.tryParse(lastLevelData.$1);
      if (lastLevelNr != null && levelNr != lastLevelNr) {
        loadLevel(lastLevelNr);
      }
    } else {
      variousTooltip = "Restored from cloud.";
      notifyListeners();
    }
    */
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

  Future<void> _createModels(LevelData level) async {
    levelNr = level.nr;
    tooltipStart = level.tooltipStart;
    tooltipEnd = level.tooltipEnd;
    if (tooltipStart.isEmpty) {
      tooltipStart =
          "Welcome back, I hope you've been well since our last session.";
    }

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
    notifyListeners();
    final nextLevelNr = levelNr + 1;
    /*
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
    */
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

  Future<void> loadLevelFromSelection(LsLevel.Level selectedLevel) async {
    await loadLevel(selectedLevel.nr, fromLevelSelect: true);
  }

  Future<void> loadLevel(int nr, {bool fromLevelSelect = false}) async {
    /*
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
    */
  }

  Future<void> assignInitialLevelValues(
      LevelData level, (String, String)? previousStory,
      {bool fromLevelSelect = false}) async {
    levelNr = level.nr;
    tooltipStart = level.tooltipStart;
    tooltipEnd = level.tooltipEnd;
    manipulationEnabled = level.manipulationEnabled;

    await pictureModel.initializePicture(level);

    fieldModel.initializeLevel(level);

    final canLettersBeRemovedMore = fieldModel.isRemoveLettersAvailable();
    setLettersCanBeRemoved(canLettersBeRemovedMore);
    levelCompleted = false;
    unlocked = level.unlocked;
    lettersAnimationFadeOutDuration = 1750;
    notifyListeners();
    if (levelNr >= 9) {
      showAds(levelNr);
    }
  }

  void showAds(int levelWhereToShow) {
    if (inAppPurchaseController?.isNoAdsPurchased() == false) {
      adsController?.showInterstitialAd();
    }
  }

  void _setLevelCompleted() {
    levelCompleted = true;
    fieldModel.setLevelCompleted();
    pictureModel.setLevelComplete();
    notifyListeners();
  }

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

   int getUnlockedLevelsCountForCategory(String categoryId) {
    // Example logic:
    // 1. Get all packs that belong to this categoryId.
    // 2. For each pack, get its unlocked level count.
    // 3. Return the sum.
    int count = 123;
    // for (var pack in allPacks) {
    //   if (pack.categoryId == categoryId) {
    //     count += getUnlockedLevelsCount(pack.id);
    //   }
    // }
    return count;
  }

  int getUnlockedLevelsCountForPack(String packId) {
    // Example logic:
    // 1. Get all packs that belong to this categoryId.
    // 2. For each pack, get its unlocked level count.
    // 3. Return the sum.
    int count = 78;
    // for (var pack in allPacks) {
    //   if (pack.categoryId == categoryId) {
    //     count += getUnlockedLevelsCount(pack.id);
    //   }
    // }
    return count;
  }

  Future<void> _save() async {
    /*
    final level = getLevelData();
    if (level.levelCompleted) {
      level.disabledLettersCount = 0;
      level.manipulationEnabled = false;
    }
    final persistentData = level.getLevelDataBasic();
    persistence.setLevelData(persistentData);
    persistence.setLatestLevel(levelNr);

    final localMaxLevelNr =
        await persistence.getMaxLeveNrUnlockedInRange(1, 200);
    final localMaxLevelQuestNr = await persistence.getMaxLevelNrUnlocked();
    gamesServicesController?.saveGame(localMaxLevelNr, localMaxLevelQuestNr);
    */
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

