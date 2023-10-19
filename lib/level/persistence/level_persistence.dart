abstract class LevelPersistence {
  Future<void> initialize();
  Future<(String, List<String>)> getLatestLevelData();
  Future<(String, List<String>)> getLevelNr(int nr);
  Future<void> setLevelData((String, List<String>) level);
}
