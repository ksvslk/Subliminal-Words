import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:operation_hermes/game/letter_box_data.dart';
import 'package:operation_hermes/game/letter_box_state.dart';
import 'package:operation_hermes/game/level_data.dart';

class FieldModel with ChangeNotifier {
  static final _log = Logger('FieldModel');

  List<LetterBoxData> solution = [];
  List<LetterBoxData> field = [];
  int disabledLettersCount = 0;
  String word = "";

  FieldModel({required LevelData level}) {
    solution = List.generate(
        level.word.length, (index) => LetterBoxData.solutionSlot(),
        growable: false);
    field = getFieldLetters(
        solutionPick: level.word,
        disabledLettersCount: level.disabledLettersCount);
    disabledLettersCount = level.disabledLettersCount;
    word = level.word;
  }

  void putLetter(int index, LetterBoxData data,
      [LetterBoxState defaultEndState = LetterBoxState.solutionPick]) {
    _putLetterPrecheck(data);
    final preAllLetters = field.map((e) => e.letter).toList() +
        solution.map((e) => e.letter).toList();
    preAllLetters.sort();

    // add letter
    var indexOfFreeSlot = solution
        .indexWhere((element) => element.state == LetterBoxState.solutionSlot);
    if (indexOfFreeSlot != -1) {
      solution[indexOfFreeSlot].letter = data.letter;
      solution[indexOfFreeSlot].state = defaultEndState;
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

  bool isRemoveLettersAvailable() {
    var allUsableLetters = (solution + field).where((element) =>
        element.state == LetterBoxState.solutionPick ||
        element.state == LetterBoxState.fieldPick);
    return allUsableLetters.length > word.length;
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
    disabledLettersCount = disabledLettersCount + lettersToRemove.length;

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
      return true;
    } else {
      return false;
    }
  }

  void setLevelCompleted() {
    word.characters.forEachIndexed((index, letter) {
      final solutionLetter =
          field.firstWhere((element) => element.letter == letter);
      putLetter(index, solutionLetter, LetterBoxState.locked);
    });
  }

  void reset() {
    solution = List.generate(
        word.length, (index) => LetterBoxData.solutionSlot(),
        growable: false);
    for (var element in solution) { element.state = LetterBoxState.solutionSlot; }
    field = getFieldLetters(solutionPick: word, disabledLettersCount: 0);
    for (var element in field) { element.state = LetterBoxState.fieldPick; }
    disabledLettersCount = 0;
    notifyListeners();
  }

  // PRECONDITIONS: Total letters count > solution word length
  // POSTCONDITIONS:
  // 1) Total letters count >= solution word length
  // 2) Total letters can create solution word

  // Assert tests
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
