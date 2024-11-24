import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:logging/logging.dart';
import 'package:operation_hermes/game/level_data.dart';
import 'package:operation_hermes/level/persistence/level_persistence.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart' show rootBundle;

const latestLevel = "LATEST_LEVEL";
const maxLevel = "MAX_LEVEL";

class LocalStorageLevelPersistence extends LevelPersistence {
  static final _log = Logger('LocalStorageLevelPersistence');

  final Future<SharedPreferences> instanceFuture =
      SharedPreferences.getInstance();

  @override
  Future<void> initialize() async {
    //_assertLevelsCorrectness('assets/other/levels.json');
    //_assertLevelsCorrectness('assets/other/levels2.json');
    final prefs = await instanceFuture;
    if (!prefs.containsKey('initialized')) {
      // Prepopulate
      await addInitialLevelsForPack('assets/other/levels.json', 1);
      // Mark the prefs as initialized
      await prefs.setBool('initialized', true);
    }

    if (!prefs.containsKey("initialized2")) {
      await addInitialLevelsForPack('assets/other/levels2.json', 2);
      await prefs.setBool('initialized2', true);
      final latestLevelNr = await getMaxLevelNrUnlocked();
      if (latestLevelNr == 100) {
        setLatestLevel(101);
      }
    }

    if (!prefs.containsKey("initialized3")) {
      await addFirstNotificationLevel();
      await prefs.setBool('initialized3', true);
      final latestLevelNr = await getMaxLevelNrUnlocked();
      if (latestLevelNr == 200) {
        setLatestLevel(201);
      }
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
  Future<List<LevelData>> getAllLevelsForPack(int packNr) async {
    final prefs = await instanceFuture;
    int startNr = 1;
    int endNr = 100;
    if (packNr == 2) {
      startNr = 101;
      endNr = 200;
    }
    if (packNr == 3) {
      startNr = 201;
      endNr = await getMaxLevelInPersistence();
    }
    List<LevelData> levels = List.empty(growable: true);
    for (var i = startNr; i <= endNr; i++) {
      final levelStrings = prefs.getStringList(i.toString());
      if (levelStrings != null) {
        final levelData = LevelData.from((i.toString(), levelStrings));
        levels.add(levelData);
      }
    }
    return levels;
  }

  @override
  Future<void> addInitialLevelsForPack(String filePath, int packNr) async {
    rootBundle.loadString(filePath).then((String jsonString) {
      List<dynamic> jsonArray = jsonDecode(jsonString);
      for (var level in jsonArray) {
        final levelData = LevelData(
            level['nr'],
            level['word'].toString().toUpperCase(),
            level['story'],
            "assets/levels${packNr >= 2 ? 2 : ''}/${level['nr']}.jpg",
            "assets/levels${packNr >= 2 ? 2 : ''}/${level['nr']}.svg",
            level['tooltipStart'],
            level['tooltipEnd'],
            false,
            false,
            0,
            false);
        setLevelData(levelData.getLevelDataBasic());
      }
    });
  }

  Future<void> addFirstNotificationLevel() async {
    rootBundle
        .loadString('assets/other/levels3.json')
        .then((String jsonString) {
      final level = jsonDecode(jsonString);
      final levelData = LevelData(
          level['nr'],
          level['word'].toString().toUpperCase(),
          level['story'],
          "assets/levels3/${level['nr']}.webp",
          "assets/levels3/${level['nr']}.svg",
          level['tooltipStart'],
          level['tooltipEnd'],
          false,
          false,
          0,
          false);
      setLevelData(levelData.getLevelDataBasic());
    });
  }

  void _assertLevelsCorrectness(String filePath) async {
    // Path to your JSON file
    final RegExp punctuation = RegExp(r"[.,!?]");
    rootBundle.loadString(filePath).then((String jsonString) {
      // Decode the JSON string to a list of objects
      List<dynamic> jsonArray = jsonDecode(jsonString);

      // Assert the expected number of objects
      assert(jsonArray.length == 100,
          'The JSON array does not contain exactly 100 objects.');

      // Using a set to track unique words
      var words = <String>{};
      var s = List.empty(growable: true);
      for (var item in jsonArray) {
        // Assuming each object has a 'word' field
        String word = item['word'];
        String story = item['story'];
        assert(story.toLowerCase().contains(word.toLowerCase()),
            '"$story" does not contain "$word"');
        assert(word.replaceAll(punctuation, '').length <= 7,
            '$word is longer than 7 chars');

        // Add 'word' to the set
        words.add(word);
        s.add(story.replaceFirst(word, "#$word"));
        _log.log(Level.INFO, words);
        int levelNr = item["nr"] > 100 ? item["nr"] - 100 : item["nr"];
        assert(words.length == levelNr, 'Repeating $word');
      }
      // Assert if set length is not equal to 100
      assert(words.length == 100, 'The number of unique words is not 100.');
    });
  }

  @override
  Future<void> setLatestLevel(int levelNr) async {
    final prefs = await instanceFuture;
    await prefs.setInt(latestLevel, levelNr);
  }

  @override
  Future<int> getMaxLevelInPersistence() async {
    final prefs = await instanceFuture;
    final intInfinity = double.maxFinite.toInt();
    var currentMaxLevelInPersistence = 0;
    for (var i = 1; i < intInfinity; i++) {
      final levelStrings = prefs.getStringList(i.toString());
      if (levelStrings != null) {
        currentMaxLevelInPersistence = i;
      } else {
        break;
      }
    }
    return currentMaxLevelInPersistence;
  }

  @override
  Future<int> getMaxLevelNrUnlocked() async {
    final prefs = await instanceFuture;
    final maxLevel = await getMaxLevelInPersistence();
    List<LevelData> levels = List.empty(growable: true);
    for (var i = 1; i < maxLevel; i++) {
      final levelStrings = prefs.getStringList(i.toString());
      if (levelStrings != null) {
        final levelData = LevelData.from((i.toString(), levelStrings));
        levels.add(levelData);
      }
    }
    return levels.lastWhereOrNull((element) => element.unlocked == true)?.nr ??
        1;
  }

  @override
  Future<void> unlockLevelsUntil(int levelNr) async {
    final prefs = await instanceFuture;
    for (var i = 1; i <= levelNr; i++) {
      final levelStrings = prefs.getStringList(i.toString());
      if (levelStrings != null) {
        var levelData = LevelData.from((i.toString(), levelStrings));
        levelData.unlocked = true;
        final basicData = levelData.getLevelDataBasic();
        await setLevelData(basicData);
      }
    }
  }
}
