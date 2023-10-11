import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:operation_hermes/game/letter_box_data.dart';
import 'package:operation_hermes/game/letter_box_state.dart';

class LevelModel with ChangeNotifier {
  bool levelComplete;
  final String word;
  final String picturePath;
  List<LetterBoxData> solution;
  List<LetterBoxData> field;
  static const testSolution = "INDREK";

  LevelModel({List<LetterBoxData>? solution, List<LetterBoxData>? field})
      : word = testSolution,
        solution = List.generate(
            testSolution.length, (index) => LetterBoxData.solutionSlot(),
            growable: false),
        field = getFieldLetters(testSolution)
            .map((e) => LetterBoxData.fieldPick(e))
            .toList(),
        picturePath = 'assets/levels/1.jpg',
        levelComplete = false;

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

  void removeArbitaryLetters(int count) {
    var potentialFieldRemovables = field.where((element) =>
        element.state == LetterBoxState.fieldPick &&
        !word.contains(element.letter)).toList();
    var potentialSolutionRemovables = List<LetterBoxData>.empty();
    var finalRemovables = List<LetterBoxData>.empty();

    // if [lettersCountMissingFromRemoval] is bigger than or equal 0 it means field has the needed letters and nothing has to be done, we take letters from [potentialFieldRemovables]
    // if it is smaller than 0 we need to get X amount which is abs(lettersCountMissingFromRemoval) more letters from solution
    var lettersCountMissingFromRemoval = count - potentialFieldRemovables.length;

    if (lettersCountMissingFromRemoval < 0) {
      potentialFieldRemovables = solution.where((element) =>
          element.state == LetterBoxState.solutionPick &&
          !word.contains(element.letter)).toList();
      potentialSolutionRemovables = potentialFieldRemovables.take(lettersCountMissingFromRemoval.abs()).toList();
      finalRemovables = finalRemovables + potentialSolutionRemovables;
    } else {
      finalRemovables = potentialFieldRemovables.take(count).toList();
    }

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
