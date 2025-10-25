import 'package:logging/logging.dart';
import 'package:operation_hermes/data/sw_level.dart';
import 'package:operation_hermes/persistence/level_persistence.dart';
import 'package:shared_preferences/shared_preferences.dart';

const latestLevel = "LATEST_LEVEL";
const maxLevel = "MAX_LEVEL";
const openLevelSelectQuest = "OPEN_QUEST_TAB";

class LocalStorageLevelPersistence extends LevelPersistence {
  
  static final _log = Logger('LocalStorageLevelPersistence');

  final Future<SharedPreferences> instanceFuture =
      SharedPreferences.getInstance();

  @override
  Future<void> setLevelData((String, List<String>) level) async {
    final prefs = await instanceFuture;
    await prefs.setStringList(level.$1, level.$2);
  }

  @override
  Future<void> setLatestLevel(int levelNr) async {
    final prefs = await instanceFuture;
    await prefs.setInt(latestLevel, levelNr);
  }
  
  @override
  Future<void> getLevelData(int nr) {
    throw UnimplementedError();
  }

  @override
  Future<SWLevel> getLatestLevelData() {
    throw UnimplementedError();
  }

}
