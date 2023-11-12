import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

class StoryModel with ChangeNotifier {
  static final _log = Logger('StoryModel');

  (String, String) currentWordAndStory = ("", "");
  (String, String) previousWordAndStory = ("", "");
  List<(String, String)> storyToCreate = List.empty(growable: true);

  void addNextStory((String, String) story)
  {
    storyToCreate.add(story);
    notifyListeners();
  }

  void clearAndAddStory()
  {
    storyToCreate.clear();
    storyToCreate.add(previousWordAndStory);
    notifyListeners();
  }

}