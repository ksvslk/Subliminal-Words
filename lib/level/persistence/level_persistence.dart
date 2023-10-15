abstract class LevelPersistence {
  Future<void> initialize();
  Future<(String, List<String>)> getLatestLevelData();
  Future<void> setLevelData((String, List<String>) level);
}
