import 'package:operation_hermes/game/level_data.dart';

abstract class LevelPersistence {
  Future<void> initialize();
  Future<(String, List<String>)> getLatestLevelData();
  Future<(String, List<String>)> getLevelNr(int nr);
  Future<(String, String)?> getLastLevelWordAndStory(int lastLevelNr);
  Future<int> getMaxLevelNrUnlocked();
  Future<void> setLevelData((String, List<String>) level);
  Future<void> setLatestLevel(int levelNr);
  Future<List<LevelData>> getAllLevelsForPack(int packNr);
  Future<void> unlockLevelsUntil(int levelNr);
  Future<void> addInitialLevelsForPack(String filePath, int packNr);
  Future<int> getMaxLevelInPersistence();
}
