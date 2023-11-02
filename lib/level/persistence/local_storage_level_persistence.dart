import 'dart:convert';
import 'dart:io';

import 'package:operation_hermes/game/level_data.dart';
import 'package:operation_hermes/level/persistence/level_persistence.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart' show rootBundle;

const latestLevel = "LATEST_LEVEL";

class LocalStorageLevelPersistence extends LevelPersistence {
  final Future<SharedPreferences> instanceFuture =
      SharedPreferences.getInstance();

  @override
  Future<void> initialize() async {
    _assertUniqueWordsInLevels();
    final prefs = await instanceFuture;
    if (!prefs.containsKey('initialized')) {
      // Prepopulate
      var level1 = LevelData(
          1,
          "SUN",
          "In a world of shadows and despair, hope seemed as far away as the morning sun.",
          "assets/levels/1.jpg",
          "assets/levels/1.svg",
          false,
          false,
          0,
          false);
      var level2 = LevelData(
          2,
          "OLD",
          "Max's daily life was a constant battle against the limits imposed by his poor old neighborhood.",
          "assets/levels/2.jpg",
          "assets/levels/2.svg",
          false,
          false,
          0,
          false);
      var level3 = LevelData(
          3,
          "FEAR",
          "Every night, he faced his greatest fear by walking through the darkest streets, undeterred.",
          "assets/levels/3.jpg",
          "assets/levels/3.svg",
          false,
          false,
          0,
          false);
      var level4 = LevelData(
          4,
          "STRONG",
          "Navigating through the heart of the city, each obstacle he overcame made him strong.",
          "assets/levels/4.jpg",
          "assets/levels/4.svg",
          false,
          false,
          0,
          false);
      var level5 = LevelData(
          4,
          "COURAGE",
          "He stood up to bullies, thugs, and criminals, demonstrating remarkable courage.",
          "assets/levels/5.jpg",
          "assets/levels/5.svg",
          false,
          false,
          0,
          false);
      setLevelData(level1.getLevelDataBasic());
      setLevelData(level2.getLevelDataBasic());
      setLevelData(level3.getLevelDataBasic());
      setLevelData(level4.getLevelDataBasic());
      setLevelData(level5.getLevelDataBasic());

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
    } else {
      return null;
    }
  }

  @override
  Future<List<LevelData>> getAllLevels() async {
    final prefs = await instanceFuture;
    List<LevelData> levels = List.empty(growable: true);
    for (var i = 0; i < 100; i++) {
      final levelStrings = prefs.getStringList(i.toString());
      if (levelStrings != null) {
        final levelData = LevelData.from((i.toString(), levelStrings));
        levels.add(levelData);
      }
    }
    return levels;
  }

  void _assertUniqueWordsInLevels() async {
    // Path to your JSON file
    var filePath = 'assets/other/levels.json';

    rootBundle.loadString(filePath).then((String jsonString) {
      // Decode the JSON string to a list of objects
      List<dynamic> jsonArray = jsonDecode(jsonString);

      // Assert the expected number of objects
      assert(jsonArray.length == 100,
          'The JSON array does not contain exactly 100 objects.');

      // Using a set to track unique words
      var words = <String>{};

      for (var item in jsonArray) {
        // Assuming each object has a 'word' field
        String word = item['word'];

        // Add 'word' to the set
        words.add(word);
      }

      // Assert if set length is not equal to 100
      assert(words.length == 100, 'The number of unique words is not 100.');

      print('All words are unique and their count is 100.');
    });
  }
}
