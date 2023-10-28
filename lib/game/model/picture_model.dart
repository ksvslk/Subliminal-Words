import 'dart:math';
import 'package:flutter/services.dart';
import 'package:operation_hermes/game/level_data.dart';
import 'package:xml/xml.dart';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:operation_hermes/game/svg_letter.dart';

class PictureModel with ChangeNotifier {
  static final _log = Logger('PictureModel');

  final maxZoom = 1.0;
  final minZoom = 0.1;
  final zoomStep = 0.1;

  double scale;
  int quarterTurn;
  String picturePath;
  String svgPath;
  List<SvgLetter> highlightLetters = [];

  PictureModel(
      {required this.scale,
      required this.quarterTurn,
      required this.picturePath,
      required this.svgPath}) {
    _loadSvgLetters(svgImage: svgPath).then((loadedLetters) {
      highlightLetters = loadedLetters;
      notifyListeners();
    });
  }

  Future<void> initializePicture(LevelData level) async
  {
    scale = 1.0;
    quarterTurn = 0;
    picturePath = level.picturePath;
    svgPath = level.svgPath;
    await _loadSvgLetters(svgImage: svgPath).then((loadedLetters) {
      highlightLetters = loadedLetters;
      highlightLetters.forEach((element) {
      _log.log(Level.INFO, "${element.letter}:${element.show}");
        
      },);
      notifyListeners();
    });
  }

  void setLevelComplete()
  {
    for (var element in highlightLetters) {element.show = true;}
  }

  void setScaleDown() {
    var newScale = (scale - zoomStep);
    newScale = double.parse((newScale).toStringAsFixed(1));
    scale = newScale <= minZoom ? minZoom : newScale;
    notifyListeners();
  }

  void setScaleUp() {
    var newScale = (scale + zoomStep);
    newScale = double.parse((newScale).toStringAsFixed(1));
    scale = newScale >= maxZoom ? maxZoom : newScale;
    notifyListeners();
  }

  void setNextQuarterTurn() {
    quarterTurn =
        quarterTurn == 3 ? quarterTurn = 0 : quarterTurn = quarterTurn + 1;
    notifyListeners();
  }

  void highlightLetter() {
    if (!highlightLetters.every((p0) => p0.show == false)) return;
    var allHintsGiven =
        highlightLetters.every((element) => element.hintGiven == true);
    List<int> candidateIndices = highlightLetters
        .asMap()
        .entries
        .where((entry) => allHintsGiven
            ? entry.value.show == false
            : (entry.value.hintGiven == false && entry.value.show == false))
        .map((entry) => entry.key)
        .toList();
    var letterIndexToHighlight = candidateIndices.sample(1, Random());
    if (letterIndexToHighlight.isNotEmpty) {
      highlightLetters[letterIndexToHighlight.first].show = true;
      highlightLetters[letterIndexToHighlight.first].hintGiven = true;
      _log.info(() =>
          'Showing letter - ${highlightLetters[letterIndexToHighlight.first].letter} with show - ${highlightLetters[letterIndexToHighlight.first].show}');
    }
    notifyListeners();
  }

  void hideLetter(String letter) {
    int index = highlightLetters.indexWhere((item) => item.letter == letter);
    if (index != -1) {
      highlightLetters[index].show = false;
      _log.info(() =>
          'Turned ${highlightLetters[index].letter} with show - ${highlightLetters[index].show}');
      notifyListeners();
    }
  }

  Future<List<SvgLetter>> _loadSvgLetters({required String svgImage}) async {
    List<SvgLetter> maps = [];
    String generalString = await rootBundle.loadString(svgImage);
    XmlDocument document = XmlDocument.parse(generalString);
    final allPaths = document.findAllElements('path');
    for (var element in allPaths) {
      String name = element.getAttribute('id').toString();
      String path = element.getAttribute('d').toString();
      var svgLetter = SvgLetter(letterPath: path, letterName: name);
      maps.add(svgLetter);
    }
    return maps;
  }

  void reset() {
    scale = 1.0;
    quarterTurn = 0;
    _log.log(Level.INFO, "Reseting PictureModel. PictureModel listeners - $hasListeners");
    notifyListeners();
  }
}
