import 'dart:math';
import 'package:logging/logging.dart';
import 'package:operation_hermes/game/level_data.dart';
import 'package:xml/xml.dart';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:operation_hermes/game/letter_box_data.dart';
import 'package:operation_hermes/game/letter_box_state.dart';
import 'package:operation_hermes/game/svg_letter.dart';

class LevelModel with ChangeNotifier {
  LevelData levelData;
  List<LetterBoxData> solution;
  List<LetterBoxData> field;
  List<SvgLetter> svgLetters = [];

  bool removeLettersAvailable = true;

  static final _log = Logger('LevelModel');

  LevelModel({required LevelData level})
      : levelData = level,
        solution = List.generate(
            level.word.length, (index) => LetterBoxData.solutionSlot(),
            growable: false),
        field = getFieldLetters(
            solutionPick: level.word,
            disabledLettersCount: level.disabledLettersCount) {
    loadSvgLetters(svgImage: level.svgPath).then((loadedLetters) {
      svgLetters = loadedLetters;
      notifyListeners();
    });
  }

  void reset() {
    levelData.disabledLettersCount = 0;
    levelData.levelCompleted = false;
    solution = List.generate(
        levelData.word.length, (index) => LetterBoxData.solutionSlot(),
        growable: false);
    field = getFieldLetters(
        solutionPick: levelData.word,
        disabledLettersCount: levelData.disabledLettersCount);
    notifyListeners();
  }

  void putLetter(int index, LetterBoxData data) {
    _putLetterPrecheck(data);
    final preAllLetters = field.map((e) => e.letter).toList() +
        solution.map((e) => e.letter).toList();
    preAllLetters.sort();

    // add letter
    var indexOfFreeSlot = solution
        .indexWhere((element) => element.state == LetterBoxState.solutionSlot);
    if (indexOfFreeSlot != -1) {
      solution[indexOfFreeSlot].letter = data.letter;
      solution[indexOfFreeSlot].state = LetterBoxState.solutionPick;
      data.letter = '';
      data.state = LetterBoxState.fieldSlot;
    }
    _postCheck(preAllLetters);
    _invariantCheck();
  }

  void removeLetter(int index, LetterBoxData data) {
    _removeLetterPrecheck(data);
    final preAllLetters = field.map((e) => e.letter).toList() +
        solution.map((e) => e.letter).toList();
    preAllLetters.sort();
    var indexOfFreeFieldSlot = field
        .indexWhere((element) => element.state == LetterBoxState.fieldSlot);
    if (indexOfFreeFieldSlot != -1) {
      field[indexOfFreeFieldSlot].letter = data.letter;
      field[indexOfFreeFieldSlot].state = LetterBoxState.fieldPick;
      data.letter = '';
      data.state = LetterBoxState.solutionSlot;
    }
    _postCheck(preAllLetters);
    _invariantCheck();
  }

  // PRECONDITIONS: Total letters count > solution word length
  // POSTCONDITIONS:
  // 1) Total letters count >= solution word length
  // 2) Total letters can create solution word

  void activatePinch() {
    levelData.zoomRewarded = true;
    notifyListeners();
  }

  bool isRemoveLettersAvailable() {
    var allUsableLetters = (solution + field).where((element) =>
        element.state == LetterBoxState.solutionPick ||
        element.state == LetterBoxState.fieldPick);
    return allUsableLetters.length > levelData.word.length;
  }

  void postTotalLettersMoreOrEqualToSolutionLength() {
    var allUsableLetters = (solution + field).where((element) =>
        element.state == LetterBoxState.solutionPick ||
        element.state == LetterBoxState.fieldPick);
    assert(allUsableLetters.length >= levelData.word.length);
  }

  void postLettersAvailableCanCreateSolution() {
    var allUsableLetters = ((solution + field).where((element) =>
        element.state == LetterBoxState.solutionPick ||
        element.state == LetterBoxState.fieldPick));
    var chars = allUsableLetters.mapIndexed((index, element) => element.letter);
    levelData.word.split('').forEach((element) {
      assert(chars.contains(element));
    });
  }

  void remove3ArbitaryLetters() {
    var count = 3;
    var solutionWord = levelData.word.split('');

    var allPickableLetters = (solution + field).where((element) =>
        element.state == LetterBoxState.fieldPick ||
        element.state == LetterBoxState.solutionPick);

    var candidateLetters = allPickableLetters.where((value) {
      var isNotInSolution = !solutionWord.contains(value.letter);
      if (isNotInSolution) solutionWord.remove(value.letter);
      return isNotInSolution;
    });

    if (candidateLetters.length < 3) {
      count = candidateLetters.length;
    }
    var lettersToRemove = candidateLetters.toList().sample(count, Random(1337));

    levelData.disabledLettersCount =
        levelData.disabledLettersCount + lettersToRemove.length;

    for (var element in lettersToRemove) {
      if (element.state == LetterBoxState.fieldPick) {
        element.state = LetterBoxState.removed;
      } else if (element.state == LetterBoxState.solutionPick) {
        var indexOfFreeFieldSlot = field
            .indexWhere((element) => element.state == LetterBoxState.fieldSlot);
        if (indexOfFreeFieldSlot != -1) {
          field[indexOfFreeFieldSlot].letter = element.letter;
          field[indexOfFreeFieldSlot].state = LetterBoxState.removed;
          element.letter = '';
          element.state = LetterBoxState.solutionSlot;
        }
      }
    }

    removeLettersAvailable = isRemoveLettersAvailable();
    notifyListeners();
    postLettersAvailableCanCreateSolution();
    postTotalLettersMoreOrEqualToSolutionLength();
  }

  bool isLastLetter() {
    var solutionLength = solution.fold(
        0,
        (previousValue, element) =>
            element.state == LetterBoxState.solutionPick ||
                    element.state == LetterBoxState.locked
                ? previousValue + 1
                : previousValue);
    return solutionLength >= levelData.word.length;
  }

  bool checkForWin() {
    var solutionString = solution.map((e) => e.letter).join("");
    if (solutionString == levelData.word) {
      for (var element in solution) {
        element.state = LetterBoxState.locked;
      }
      levelData.levelCompleted = true;
      notifyListeners();
      return true;
    } else {
      return false;
    }
  }

  void showRandomPictureLetter() {
    if (!svgLetters.every((p0) => p0.show == false)) return;
    var allHintsGiven =
        svgLetters.every((element) => element.hintGiven == true);
    List<int> candidateIndices = svgLetters
        .asMap()
        .entries
        .where((entry) => allHintsGiven
            ? entry.value.show == false
            : (entry.value.hintGiven == false && entry.value.show == false))
        .map((entry) => entry.key)
        .toList();
    var letterIndexToHighlight = candidateIndices.sample(1, Random());
    if (letterIndexToHighlight.isNotEmpty) {
      svgLetters[letterIndexToHighlight.first].show = true;
      svgLetters[letterIndexToHighlight.first].hintGiven = true;
      _log.info(() =>
          'Showing letter: ${svgLetters[letterIndexToHighlight.first].letter} with show: ${svgLetters[letterIndexToHighlight.first].show}');
    }
    notifyListeners();
  }

  void hidePictureLetter(String letter) {
    int index = svgLetters.indexWhere((item) => item.letter == letter);
    if (index != -1) {
      svgLetters[index].show = false;
      _log.info(() =>
          'Turned ${svgLetters[index].letter} with show: ${svgLetters[index].show}');
      notifyListeners();
    }
  }

  void _invariantCheck() {
    assert(
        !solution.any((element) => (element.state == LetterBoxState.fieldPick ||
            element.state == LetterBoxState.fieldSlot)),
        "Solution should never contain items with 'field' state");
    assert(
        !field.any((element) => (element.state == LetterBoxState.solutionPick ||
            element.state == LetterBoxState.solutionSlot)),
        "Field should never contain items with 'solution' state");
    assert(field.length == 14, "Field should always have 14 data items.");
    assert(solution.length == levelData.word.length,
        "Solution data list length should always be same as the solution word length.");
    // at any time solution must be able to be formed by solution+field letters.
  }

  void _putLetterPrecheck(LetterBoxData data) {
    assert(data.state == LetterBoxState.fieldPick,
        "Pre check for picking letter failed.");
  }

  void _removeLetterPrecheck(LetterBoxData data) {
    assert(data.state == LetterBoxState.solutionPick,
        "Pre check for picking letter failed.");
  }

  void _postCheck(List<String> preAllLetters) {
    final postAllLetters = field.map((e) => e.letter).toList() +
        solution.map((e) => e.letter).toList();
    postAllLetters.sort();
    Function deepEq = const DeepCollectionEquality().equals;
    assert(deepEq(preAllLetters, postAllLetters),
        "Letters should remain same after all operations.");
  }
}

Future<List<SvgLetter>> loadSvgLetters({required String svgImage}) async {
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

List<LetterBoxData> getFieldLetters(
    {required String solutionPick, required int disabledLettersCount}) {
  final random = Random();
  var alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.characters;

  // find all letters that are not in solution
  var lettersWithoutSolution =
      alphabet.toSet().difference(solutionPick.characters.toSet());

  // create a list that is shorter than the solution (exactly solution length shorter)
  var shuffledUnique14WithoutSolutionLetters = lettersWithoutSolution
      .take(14 - solutionPick.length)
      .mapIndexed((index, element) => (index < disabledLettersCount)
          ? LetterBoxData.removed(element)
          : LetterBoxData.fieldPick(element))
      .toList();

  // add the solution to the end of unique strings list and shuffle
  shuffledUnique14WithoutSolutionLetters
      .addAll(solutionPick.characters.map((e) => LetterBoxData.fieldPick(e)));
  shuffledUnique14WithoutSolutionLetters.shuffle(random);

  assert(
      solutionPick.characters.every((element) =>
          shuffledUnique14WithoutSolutionLetters
              .map((e) => e.letter)
              .contains(element)),
      "Field does not contain all required solution letters.");

  return shuffledUnique14WithoutSolutionLetters;
}
