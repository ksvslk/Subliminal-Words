import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:operation_hermes/game/level_data.dart';
import 'package:operation_hermes/level/persistence/level_persistence.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart' show rootBundle;

const latestLevel = "LATEST_LEVEL";

class LocalStorageLevelPersistence extends LevelPersistence {
  static final _log = Logger('LocalStorageLevelPersistence');


  final Future<SharedPreferences> instanceFuture =
      SharedPreferences.getInstance();

  @override
  Future<void> initialize() async {
    _assertUniqueWordsInLevels();
    final prefs = await instanceFuture;
    if (!prefs.containsKey('initialized')) {
      // Prepopulate
      await _addInitialLevels();
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

  Future<void> _addInitialLevels() async {
    var filePath = 'assets/other/levels.json';
    rootBundle.loadString(filePath).then((String jsonString) {
      List<dynamic> jsonArray = jsonDecode(jsonString);
      for (var level in jsonArray) {
        final levelData = LevelData(
          level['nr'],
          level['word'].toString().toUpperCase(),
          level['story'],
          "assets/levels/${level['nr']}.jpg",
          "assets/levels/${level['nr']}.svg",
          false,
          false,
          0,
          false);
          setLevelData(levelData.getLevelDataBasic());
      }
    });
  }

  void _assertUniqueWordsInLevels() async {
    // Path to your JSON file
    var filePath = 'assets/other/levels.json';
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
        assert(story.toLowerCase().contains(word.toLowerCase()), '"$story" does not contain "$word"');
        assert(word.replaceAll(punctuation, '').length <= 7, '$word is longer than 7 chars');

        // Add 'word' to the set
        words.add(word);
        s.add(story.replaceFirst(word, "#$word"));
        assert(words.length == item["nr"], 'Repeating $word');
      }

      _log.log(Level.INFO, s.toString());
   
      // Assert if set length is not equal to 100
      assert(words.length == 100, 'The number of unique words is not 100.');

      print('All words are unique and their count is 100.');
    });
  }
}
