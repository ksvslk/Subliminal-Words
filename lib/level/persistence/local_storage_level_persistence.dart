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
              "SUN",
              "Amid shadows and bleak landscapes, hope was as distant as the morning sun.",
              "assets/levels/1.jpg",
              "assets/levels/1.svg",
              false,
              false,
      0,false);
      var level2 = LevelData(
              2,
              "OLD",
              "Each day, a struggle against his world's confines, inspired by legends old.",
              "assets/levels/2.jpg",
              "assets/levels/2.svg",
              false,
              false,
      0,false);
         var level3 = LevelData(
              3,
              "FEAR",
              "Nightly, Max ventured into darkness, unflinching, facing his deepest fear.",
              "assets/levels/1.png",
              "assets/levels/1.svg",
              false,
              false,
      0,false);
           var level4 = LevelData(
              4,
              "STRONG",
              "Journeying through the city's heart, every corner, he grew strong.",
              "assets/levels/2.jpg",
              "assets/levels/2.svg",
              false,
              false,
      0,false);
      setLevelData(level1.getLevelDataBasic());
      setLevelData(level2.getLevelDataBasic());
      setLevelData(level3.getLevelDataBasic());
      setLevelData(level4.getLevelDataBasic());

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
    List<String> levelInfo = prefs.getStringList(nr.toString())!;
    return (nr.toString(), levelInfo);
  }
  
  @override
  Future<(String, String)?> getLastLevelWordAndStory(int lastLevelNr) async {
    final prefs = await instanceFuture;
    List<String>? levelInfo = prefs.getStringList(lastLevelNr.toString());
    if (levelInfo != null) {
      final previousLevel = LevelData.from((lastLevelNr.toString(), levelInfo));
      return (previousLevel.word, previousLevel.story);
    } else  {
      return null;
    }
  }
  
  @override
  Future<List<LevelData>> getAllLevels() async {
    final prefs = await instanceFuture;
    List<LevelData> levels = List.empty(growable: true);
    for (var i = 0; i < 100; i++) {
      final levelStrings = prefs.getStringList(i.toString());
      if (levelStrings != null)
      {
        final levelData = LevelData.from((i.toString(), levelStrings));
        levels.add(levelData);
      }
    }
    return levels;
  }
  
}
