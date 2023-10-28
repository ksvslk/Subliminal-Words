import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:operation_hermes/game/model/field_model.dart';
import 'package:operation_hermes/game/level_data.dart';
import 'package:operation_hermes/game/model/picture_model.dart';
import 'package:operation_hermes/level/persistence/level_persistence.dart';

class LevelModel with ChangeNotifier {
  final LevelPersistence persistence;
  ValueNotifier<AppLifecycleState>? _lifecycleNotifier;

  static final _log = Logger('LevelModel');

  int levelNr = -1;
  (String, String) currentWordAndStory = ("", "");
  (String, String) previousWordAndStory = ("", "");
  bool levelCompleted = false;
  late PictureModel pictureModel;
  late FieldModel fieldModel;

  bool remove3Available = false;
  bool manipulationEnabled = false;

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
    currentWordAndStory = (level.word, level.story);

    previousWordAndStory = previousStory ?? ("", "And so it starts...");
    previousWordAndStory = (
      previousWordAndStory.$1.toLowerCase(),
      previousWordAndStory.$2
    );

    manipulationEnabled = level.manipulationEnabled;

    pictureModel = PictureModel(
        scale: 1.0,
        quarterTurn: 0,
        picturePath: level.picturePath,
        svgPath: level.svgPath);

    fieldModel = FieldModel(level: level);

    final canLettersBeRemovedMore = fieldModel.isRemoveLettersAvailable();
    setLettersCanBeRemoved(canLettersBeRemovedMore);

    if (level.levelCompleted) _setLevelCompleted();
  }

  void setLettersCanBeRemoved(bool newValue) {
    remove3Available = newValue;
    notifyListeners();
  }

  Future<void> nextLevel() async
  {
    loadLevel(levelNr +1);
  }

  Future<void> loadLevel(int nr) async {
    _log.log(Level.INFO, "loadLevel");
    persistence.getLevelNr(nr).then((currentLevel) {
      final level = LevelData.from(currentLevel);
      persistence
          .getLastLevelWordAndStory(nr - 1)
          .then((prevLevelWordAndStory) {
        _log.info(previousWordAndStory);
        assignInitialLevelValues(level, prevLevelWordAndStory);
        _log.log(Level.INFO,
            "Assigned level values for level nr: $nr and previous level story is: $previousWordAndStory");
      }).onError((error, stackTrace) {
        _log.severe("Error getting the story for level ${nr - 1}", error);
      });
    }).onError((error, stackTrace) {
      _log.severe("Could not load the level nr: $nr", error);
    });
  }

  Future<void> assignInitialLevelValues(
      LevelData level, (String, String)? previousStory) async {
    

    // LevelModel
    levelNr = level.nr;
    currentWordAndStory = (level.word, level.story);

    previousWordAndStory = previousStory ?? ("", "And so it starts...");
    previousWordAndStory = (
      previousWordAndStory.$1.toLowerCase(),
      previousWordAndStory.$2
    );

    // PictureModel
    await pictureModel.initializePicture(level);

    // FieldModel
    fieldModel.initializeLevel(level);

    final canLettersBeRemovedMore = fieldModel.isRemoveLettersAvailable();
    setLettersCanBeRemoved(canLettersBeRemovedMore);
    levelCompleted = false;
    notifyListeners();
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
    notifyListeners();
    return win;
  }

  LevelData getLevelData() {
    return LevelData(
        levelNr,
        fieldModel.word,
        currentWordAndStory.$2,
        pictureModel.picturePath,
        pictureModel.svgPath,
        manipulationEnabled,
        levelCompleted,
        fieldModel.disabledLettersCount);
  }

  Future<void> _save() async {
    final level = getLevelData();
    final persistentData = level.getLevelDataBasic();
    persistence.setLevelData(persistentData);
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
