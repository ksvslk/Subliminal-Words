import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

class HintModel with ChangeNotifier {
  static final _log = Logger('HintModel');

  bool lettersCanBeRemoved = false;

  bool removalRewarded = true;
  bool zoomRewarded = false;
  bool highlightRewarded = true;

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

}
