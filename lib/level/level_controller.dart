import 'package:flutter/material.dart';
import 'package:operation_hermes/game/level_data.dart';
import 'package:operation_hermes/game/level_model.dart';
import 'package:operation_hermes/level/persistence/level_persistence.dart';

class LevelController {
  final LevelPersistence _persistence;

  ValueNotifier<AppLifecycleState>? _lifecycleNotifier;
  ValueNotifier<LevelData?> currentLevel = ValueNotifier(null);
  LevelModel? levelModel;

  LevelController({required LevelPersistence persistence})
      : _persistence = persistence;

  Future<void> initialize() async {
    final latestLevelData = await _persistence.initialize().then((value) async {
      return await _persistence.getLatestLevelData();
    });
    currentLevel.value = LevelData.from(latestLevelData);
    levelModel = LevelModel(level: currentLevel.value!);
  }

  void attachLifecycleNotifier(ValueNotifier<AppLifecycleState> lifecycleNotifier) {
    _lifecycleNotifier?.removeListener(_handleAppLifecycle);
    lifecycleNotifier.addListener(_handleAppLifecycle);
    _lifecycleNotifier = lifecycleNotifier;
  }

  void _handleAppLifecycle() {
    switch (_lifecycleNotifier!.value) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _save();
      case AppLifecycleState.resumed:
      case AppLifecycleState.inactive:
        break;
    }
  }

  void dispose() {
    _lifecycleNotifier?.removeListener(_handleAppLifecycle);
  }

  void _save() {
    _persistence.setLevelData(levelModel!.levelData.getLevelData());
  }
}
