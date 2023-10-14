import 'dart:math';
import 'package:xml/xml.dart';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:operation_hermes/game/letter_box_data.dart';
import 'package:operation_hermes/game/letter_box_state.dart';
import 'package:operation_hermes/game/svg_letter.dart';

class LevelModel with ChangeNotifier {
  bool levelComplete;
  final String word;
  final String picturePath;
  List<LetterBoxData> solution;
  List<LetterBoxData> field;

  List<SvgLetter> svgLetters = [];
  bool svgLettersLoaded = false;

  bool removeLettersAvailable = true;
  bool zoomAndRotateEnabled = false;

  String letterToShow = ''; // TODO: duplicate

  static const testSolution = "ZEN";

  LevelModel({List<LetterBoxData>? solution, List<LetterBoxData>? field})
      : word = testSolution,
        solution = List.generate(
            testSolution.length, (index) => LetterBoxData.solutionSlot(),
            growable: false),
        field = getFieldLetters(testSolution)
            .map((e) => LetterBoxData.fieldPick(e))
            .toList(),
        picturePath = 'assets/levels/1.png',
        levelComplete = false {
    loadSvgLetters(svgImage: 'assets/levels/1.svg').then((loadedLetters) {
      svgLetters = loadedLetters;
      svgLettersLoaded = true;
    });
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
    zoomAndRotateEnabled = true;
    notifyListeners();
  }

  bool isRemoveLettersAvailable() {
    var allUsableLetters = (solution + field).where((element) =>
        element.state == LetterBoxState.solutionPick ||
        element.state == LetterBoxState.fieldPick);
    return allUsableLetters.length > word.length;
  }

  void postTotalLettersMoreOrEqualToSolutionLength() {
    var allUsableLetters = (solution + field).where((element) =>
        element.state == LetterBoxState.solutionPick ||
        element.state == LetterBoxState.fieldPick);
    assert(allUsableLetters.length >= word.length);
  }

  void postLettersAvailableCanCreateSolution() {
    var allUsableLetters = ((solution + field).where((element) =>
        element.state == LetterBoxState.solutionPick ||
        element.state == LetterBoxState.fieldPick));
    var chars = allUsableLetters.mapIndexed((index, element) => element.letter);
    word.split('').forEach((element) {
      assert(chars.contains(element));
    });
  }

  void remove3ArbitaryLetters() {
    var count = 3;
    var solutionWord = word.split('');

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
    return solutionLength >= word.length;
  }

  bool checkForWin() {
    var solutionString = solution.map((e) => e.letter).join("");
    if (solutionString == word) {
      for (var element in solution) {
        element.state = LetterBoxState.locked;
      }
      levelComplete = true;
      return true;
    } else {
      return false;
    }
  }

  void highlightRandomLetter() {
    var highlightedLettersSelection = svgLetters.where(
        (element) => element.hintGiven == false && element.show == false);
    var letterToHighlight = highlightedLettersSelection.sample(1, Random());
    if (letterToHighlight.isNotEmpty)
    {
      letterToHighlight.first.show = true;
      letterToHighlight.first.hintGiven = true;
      highlightedLettersSelection.forEach((element) { /*TODO: reset*/ });
    }
    notifyListeners();
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
    assert(solution.length == word.length,
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

List<String> getFieldLetters(String solutionPick) {
  final random = Random();
  var alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.characters;

  // find all letters that are not in solution
  var lettersWithoutSolution =
      alphabet.toSet().difference(solutionPick.characters.toSet());

  // create a list that is shorter than the solution (exactly solution length shorter)
  var shuffledUnique14WithoutSolutionLetters =
      lettersWithoutSolution.take(14 - solutionPick.length).toList();

  // add the solution to the end of unique strings list and shuffle
  shuffledUnique14WithoutSolutionLetters.addAll(solutionPick.characters);
  shuffledUnique14WithoutSolutionLetters.shuffle(random);

  assert(
      solutionPick.characters.every((element) =>
          shuffledUnique14WithoutSolutionLetters.contains(element)),
      "Field does not contain all required solution letters.");

  return shuffledUnique14WithoutSolutionLetters;
}
