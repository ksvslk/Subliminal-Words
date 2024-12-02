import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:operation_hermes/game/level_data.dart';

abstract class LevelPersistence {
  Future<void> initialize();
  Future<(String, List<String>)> getLatestLevelData();
  Future<(String, List<String>)> getLevelNr(int nr);
  Future<(String, String)?> getLastLevelWordAndStory(int lastLevelNr);
  Future<int> getMaxLevelNrUnlocked();
  Future<int> getMaxLeveNrUnlockedInRange(int start, int end);
  Future<void> setLevelData((String, List<String>) level);
  Future<void> setLatestLevel(int levelNr);
  Future<List<LevelData>> getAllLevelsForPack(int packNr);
  Future<void> unlockLevelsRange(int start, int end);
  Future<void> addInitialLevelsForPack(String filePath, int packNr);
  Future<int> getMaxLevelInPersistence();
  Future<void> setOpenQuestTab(bool value);
  Future<bool> getOpenQuestTab();
  Future<void> tryAddingNotificationLevel(RemoteMessage message);
}
