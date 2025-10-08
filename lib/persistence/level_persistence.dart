import 'package:operation_hermes/data/level_data.dart';

abstract class LevelPersistence {
  Future<void> setLevelData((String, List<String>) level);
  Future<void> getLevelData(int nr);
  Future<void> setLatestLevel(int levelNr);
  Future<LevelData> getLatestLevelData();
}
