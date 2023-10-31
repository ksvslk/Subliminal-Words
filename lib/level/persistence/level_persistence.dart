import 'package:operation_hermes/game/level_data.dart';

abstract class LevelPersistence {
  Future<void> initialize();
  Future<(String, List<String>)> getLatestLevelData();
  Future<(String, List<String>)> getLevelNr(int nr);
  Future<(String, String)?> getLastLevelWordAndStory(int lastLevelNr);
  Future<void> setLevelData((String, List<String>) level);
  Future<List<LevelData>> getAllLevels();
}
