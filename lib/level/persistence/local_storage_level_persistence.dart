import 'package:operation_hermes/game/level_data.dart';
import 'package:operation_hermes/level/persistence/level_persistence.dart';
import 'package:shared_preferences/shared_preferences.dart';

const latestLevel = "LATEST_LEVEL";

class LocalStorageLevelPersistence extends LevelPersistence {
  final Future<SharedPreferences> instanceFuture =
      SharedPreferences.getInstance();

  @override
  Future<void> initialize() async {
    final prefs = await instanceFuture;
    if (!prefs.containsKey('initialized')) {
      
      // Prepopulate
      var level1 = LevelData(
              1,
              "ZEN",
              "Mingi jutt mis sisaldab ZEN sõna kusagil.",
              "assets/levels/1.png",
              "assets/levels/1.svg",
              false,
              false,
      0);
      setLevelData(level1.getLevelData());

      // Mark the prefs as initialized
      await prefs.setBool('initialized', true);
    }
  }

  @override
  Future<(String, List<String>)> getLatestLevelData() async {
    final prefs = await instanceFuture;
    String lastLevelPlayed = (prefs.getInt(latestLevel) ?? 1).toString();
    List<String> lastLevelData =
        prefs.getStringList(lastLevelPlayed.toString())!;
    return (lastLevelPlayed, lastLevelData);
  }

  @override
  Future<void> setLevelData((String, List<String>) level) async {
    final prefs = await instanceFuture;
    await prefs.setStringList(level.$1, level.$2);
  }
}
