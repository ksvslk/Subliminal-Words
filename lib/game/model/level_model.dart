import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:operation_hermes/game/model/field_model.dart';
import 'package:operation_hermes/game/model/hint_model.dart';
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
  late HintModel hintModel;

  bool tempFlag = false;

  LevelModel({required this.persistence});

  Future<void> initialize() async {
    final latestLevelData = await persistence.initialize().then((value) async {
      return await persistence.getLatestLevelData();
    });
    final level = LevelData.from(latestLevelData);
    await _createModel(level);
  }

  Future<void> _createModel(LevelData level) async
  {
   if (levelCompleted) _setLevelCompleted();
    pictureModel = PictureModel(
        scale: 1.0,
        quarterTurn: 0,
        zoomEnabled: level.zoomRewarded,
        picturePath: level.picturePath,
        svgPath: level.svgPath);
    fieldModel = FieldModel(level: level);
    levelNr = level.nr;
    storyLine = level.story;
    hintModel = HintModel(
        removalRewarded: true,
        zoomRewarded: level.zoomRewarded,
        highlightRewarded: true);
    final canLettersBeRemovedMore = fieldModel.isRemoveLettersAvailable();
    hintModel.setLettersCanBeRemoved(canLettersBeRemovedMore);
  }

  void _setLevelCompleted() {
    fieldModel.setLevelCompleted();
    levelCompleted = true;
    notifyListeners();
  }

  void reset() {
    pictureModel.reset();
    fieldModel.reset();
    hintModel.reset();
    levelCompleted = false;
    notifyListeners();
  }

  void remove3ArbitaryLetters() {
    fieldModel.remove3ArbitaryLetters();
    final canLettersBeRemovedMore = fieldModel.isRemoveLettersAvailable();
    hintModel.setLettersCanBeRemoved(canLettersBeRemovedMore);
  }

  void highlightLetter() {
    pictureModel.highlightLetter();
  }

  bool isLastLetter() => fieldModel.isLastLetter();

  bool checkForWin() {
    var win = fieldModel.checkForWin();
    levelCompleted = win;
    return win;
  }

  LevelData getLevelData()
  {
    return LevelData(
      levelNr,
      fieldModel.word,
      storyLine,
      pictureModel.picturePath,
      pictureModel.svgPath,
      hintModel.zoomRewarded,
      levelCompleted,
      fieldModel.disabledLettersCount
      );
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

  Future<void> _save() async {
    final level = getLevelData();
    final persistentData = level.getLevelDataBasic();
    persistence.setLevelData(persistentData);
  }

  Future<void> loadLevel(int nr) async {
    final loadedLevel = await persistence.initialize().then((value) async {
      return await persistence.getLevelNr(nr);
    });
    final level = LevelData.from(loadedLevel);
    _createModel(level);
  }


}
