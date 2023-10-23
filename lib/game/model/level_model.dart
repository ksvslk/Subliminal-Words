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
  String storyLine = "";
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
    await _createModels(level);
    _log.log(Level.INFO, "initialize");
  }

  void testNotify() {
    notifyListeners();
  }

  Future<void> _createModels(LevelData level) async {
    levelNr = level.nr;
    storyLine = level.story;
    manipulationEnabled = level.manipulationEnabled;

    pictureModel = PictureModel(
        scale: 1.0,
        quarterTurn: 0,
        picturePath: level.picturePath,
        svgPath: level.svgPath);

    fieldModel = FieldModel(level: level);

    final canLettersBeRemovedMore = fieldModel.isRemoveLettersAvailable();
    setLettersCanBeRemoved(canLettersBeRemovedMore);

    if (levelCompleted) _setLevelCompleted();
  }

  void setLettersCanBeRemoved(bool newValue) {
    remove3Available = newValue;
    notifyListeners();
  }

  Future<void> loadLevel(int nr) async {
    _log.log(Level.INFO, "loadLevel");
    persistence.getLevelNr(nr).then((value) {
      final level = LevelData.from(value);

      // LevelModel
      levelNr = level.nr;
      storyLine = level.story;

      // PictureModel
      pictureModel.initializePicture(level);

      // FieldModel
      fieldModel.initializeLevel(level);

      final canLettersBeRemovedMore = fieldModel.isRemoveLettersAvailable();
      setLettersCanBeRemoved(canLettersBeRemovedMore);

      if (level.levelCompleted) _setLevelCompleted();
    });
  }

  void _setLevelCompleted() {
    fieldModel.setLevelCompleted();
    levelCompleted = true;
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
    return win;
  }

  LevelData getLevelData() {
    return LevelData(
        levelNr,
        fieldModel.word,
        storyLine,
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
