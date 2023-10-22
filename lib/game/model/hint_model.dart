import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:operation_hermes/game/level_data.dart';

class HintModel with ChangeNotifier {
  static final _log = Logger('HintModel');

  bool lettersCanBeRemoved = false;

  bool removalRewarded = false;
  bool zoomRewarded = false;
  bool highlightRewarded = false;

  bool remove3Purchased = true;
  bool zoomPurchased = true;
  bool highlightPurchased = true;

  HintModel(
      {required this.removalRewarded,
      required this.zoomRewarded,
      required this.highlightRewarded});

  void activateZoom() {
    zoomRewarded = true;
    notifyListeners();
  }

  void setLettersCanBeRemoved(bool value)
  {
    lettersCanBeRemoved = value;
    notifyListeners();
  }

  void initializeHints(LevelData level, bool canLettersBeRemoved)
  {
      removalRewarded = true;
      zoomRewarded = level.zoomRewarded;
      highlightRewarded = true;
      lettersCanBeRemoved = canLettersBeRemoved;
      notifyListeners();
  }

}
