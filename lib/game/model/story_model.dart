import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

class StoryModel with ChangeNotifier {
  static final _log = Logger('StoryModel');

  (String, String) currentWordAndStory = ("", "");
  (String, String) previousWordAndStory = ("", "");
  List<(String, String)> storyToCreate = List.empty(growable: true);

  void addNextStory((String, String) story)
  {
    _log.log(Level.INFO, "setLevelCompleted");
    storyToCreate.forEach((element) {_log.log(Level.INFO, element.$2);});
    storyToCreate.add(story);
    notifyListeners();
  }

}