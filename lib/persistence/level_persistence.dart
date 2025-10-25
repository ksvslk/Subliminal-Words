import 'package:operation_hermes/data/sw_level.dart';

abstract class LevelPersistence {
  Future<void> setLevelData((String, List<String>) level);
  Future<void> getLevelData(int nr);
  Future<void> setLatestLevel(int levelNr);
  Future<SWLevel> getLatestLevelData();
}
