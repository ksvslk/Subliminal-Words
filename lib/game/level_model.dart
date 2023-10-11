import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:operation_hermes/game/letter_box_data.dart';
import 'package:operation_hermes/game/letter_box_state.dart';

class LevelModel with ChangeNotifier {
  final bool levelComplete;
  final String word;
  final String picturePath;
  List<LetterBoxData> solution;
  List<LetterBoxData> field;

  LevelModel({List<LetterBoxData>? solution, List<LetterBoxData>? field})
      : word = 'BIG',
        solution = List.generate(3, (index) => LetterBoxData.solutionSlot(),
            growable: false),
        field = List.generate(
            14, (index) => LetterBoxData.fieldPick(randomLetter("")),
            growable: false),
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


  bool checkForWin() {
    if (solution.map((e) => e.letter).toString() == word) {
      for (var element in solution) {
        element.state = LetterBoxState.locked;
      }
      return true;
    }
    else {
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

String randomLetter(String solutionPick) {
  const letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  var finalLettersSet = letters.split('').toSet().difference(solutionPick.split('').toSet()).join('');
  final random = Random();
  return finalLettersSet[random.nextInt(finalLettersSet.length)];
}
