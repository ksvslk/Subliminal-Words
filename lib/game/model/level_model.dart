import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:operation_hermes/game/model/field_model.dart';
import 'package:operation_hermes/game/level_data.dart';
import 'package:operation_hermes/game/model/picture_model.dart';
import 'package:operation_hermes/game/model/story_model.dart';
import 'package:operation_hermes/level/persistence/level_persistence.dart';

class LevelModel with ChangeNotifier {
  final LevelPersistence persistence;
  ValueNotifier<AppLifecycleState>? _lifecycleNotifier;

  static final _log = Logger('LevelModel');

  int levelNr = -1;
  String tooltipStart = "";
  String tooltipEnd = "";
  bool levelCompleted = false;
  bool unlocked = false;
  late PictureModel pictureModel;
  late FieldModel fieldModel;
  late StoryModel storyModel;

  bool remove3Available = false;
  bool manipulationEnabled = false;

  bool remove3NotificationSeen = false;
  bool manipulatetNotificationSeen = false;
  bool higlightNotificationSeen = false;

  ValueNotifier<int> currentStoryCardPageNr = ValueNotifier(1);

  LevelModel({required this.persistence});

  Future<void> initialize() async {
    final latestLevelData = await persistence.initialize().then((value) async {
      return await persistence.getLatestLevelData();
    });
    final level = LevelData.from(latestLevelData);
    final previousStory = await persistence.initialize().then((value) async {
      return await persistence.getLastLevelWordAndStory(level.nr - 1);
    });
    await _createModels(level, previousStory);

    _log.log(Level.INFO, "initialize");
  }

  Future<void> _createModels(
      LevelData level, (String, String)? previousStory) async {
    levelNr = level.nr;
    tooltipStart = level.tooltipStart;
    tooltipEnd = level.tooltipEnd;

    storyModel = StoryModel();
    storyModel.previousWordAndStory =
        previousStory ?? ("", "And so it starts...");
    storyModel.currentWordAndStory = (level.word, level.story);
    storyModel.addNextStory(storyModel.previousWordAndStory);

    manipulationEnabled = level.manipulationEnabled;

    pictureModel = PictureModel(
        scale: 1.0,
        quarterTurn: 0,
        picturePath: level.picturePath,
        svgPath: level.svgPath)
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

  void hideTooltipStart() {
    tooltipStart = "";
    notifyListeners();
  }

  Future<void> nextLevel() async {
    await loadLevel(levelNr + 1);
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

    storyModel.previousWordAndStory =
        previousStory ?? ("", "And so it starts...");
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

    notifyListeners();
  }

  Future<(List<(String, String, int)>, int)>
      getAllLevelsWordAndStories() async {
    final levels = await persistence.getAllLevels();
    var index = 0;
    for (var level in levels) {
      level.story.split(' ').forEach((storyWord) {
        if (!level.unlocked) return;
        index = index + 1;
      });
    }
    return (
      levels.map((e) => (e.word.toLowerCase(), e.story, e.nr)).toList(),
      index
    );
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
    }
    notifyListeners();
    return win;
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
    final level = getLevelData();
    final persistentData = level.getLevelDataBasic();
    persistence.setLevelData(persistentData);
    persistence.setLatestLevel(levelNr);
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
        _save();
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
