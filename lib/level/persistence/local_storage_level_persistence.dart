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
      var level2 = LevelData(
              2,
              "BIGS",
              "Blablabl BIG blabla.",
              "assets/levels/2.jpg",
              "assets/levels/2.svg",
              false,
              false,
      0);
      setLevelData(level1.getLevelDataBasic());
      setLevelData(level2.getLevelDataBasic());

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
  
  @override
  Future<(String, List<String>)> getLevelNr(int nr) async {
    final prefs = await instanceFuture;
    List<String> lastLevelData =
        prefs.getStringList(nr.toString())!;
    return (nr.toString(), lastLevelData);
  }
  
}
