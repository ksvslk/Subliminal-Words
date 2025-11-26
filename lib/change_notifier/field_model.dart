import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:operation_hermes/data/letter_box_data.dart';
import 'package:operation_hermes/data/letter_box_state.dart';

class FieldModel with ChangeNotifier {
  List<LetterBoxData> solution = [];
  List<LetterBoxData> field = [];
  String word = "";

  FieldModel({required String levelWord}) {
    initializeLevel(levelWord);
  }

  void initializeLevel(String levelWord) {
    if (levelWord.isEmpty) return;
    solution = List.generate(
        levelWord.length, (index) => LetterBoxData.solutionSlot(),
        growable: false);
    field = getFieldLetters(solutionPick: levelWord, disabledLettersCount: 0);
    for (var i = 0; i < field.length; i++) {
      field[i].originalFieldIndex = i;
    }
    word = levelWord.toUpperCase();
  }

  void putLetter(int fieldIndex,
      [LetterBoxState targetState = LetterBoxState.solutionPick]) {
    _putLetterPrecheck(field[fieldIndex]);
    final preAllLetters = field.map((e) => e.letter).toList() +
        solution.map((e) => e.letter).toList();
    preAllLetters.sort();
    var indexOfFreeSolutionSlot = solution
        .indexWhere((element) => element.state == LetterBoxState.solutionSlot);
    if (indexOfFreeSolutionSlot != -1) {
      solution[indexOfFreeSolutionSlot].letter = field[fieldIndex].letter;
      solution[indexOfFreeSolutionSlot].originalFieldIndex =
          field[fieldIndex].originalFieldIndex;
      solution[indexOfFreeSolutionSlot].state = targetState;
      field[fieldIndex].letter = '';
      field[fieldIndex].state = LetterBoxState.fieldSlot;
      field[fieldIndex].originalFieldIndex = null;
      notifyListeners();
    }
    _postCheck(preAllLetters);
    _invariantCheck();
  }

  void removeLetter(int index) {
    _removeLetterPrecheck(solution[index]);
    final preAllLetters = field.map((e) => e.letter).toList() +
        solution.map((e) => e.letter).toList();
    preAllLetters.sort();

    final originalFieldIndexOfLetterInSolution =
        solution[index].originalFieldIndex;
    int? targetFieldIndex;

    if (originalFieldIndexOfLetterInSolution != null &&
        originalFieldIndexOfLetterInSolution < field.length &&
        field[originalFieldIndexOfLetterInSolution].state ==
            LetterBoxState.fieldSlot) {
      targetFieldIndex = originalFieldIndexOfLetterInSolution;
    } else {
      targetFieldIndex =
          field.indexWhere((f) => f.state == LetterBoxState.fieldSlot);
    }

    if (targetFieldIndex != -1) {
      field[targetFieldIndex].letter = solution[index].letter;
      field[targetFieldIndex].state = LetterBoxState.fieldPick;
      field[targetFieldIndex].originalFieldIndex =
          originalFieldIndexOfLetterInSolution; // Preserve original home

      solution[index].letter = '';
      solution[index].state = LetterBoxState.solutionSlot;
      solution[index].originalFieldIndex = null;
      notifyListeners();
    }
    _postCheck(preAllLetters);
    _invariantCheck();
  }

  List<LetterBoxData> getFieldLetters(
      {required String solutionPick, required int disabledLettersCount}) {
    final solutionWord = solutionPick.toUpperCase();
    final random = Random();
    var alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.characters;

    var lettersWithoutSolution =
        alphabet.toSet().difference(solutionWord.characters.toSet());

    var shuffledUnique14WithoutSolutionLetters = lettersWithoutSolution
        .take(14 - solutionWord.length)
        .mapIndexed((index, element) => (index < disabledLettersCount)
            ? LetterBoxData.removed(element)
            : LetterBoxData.fieldPick(element))
        .toList();

    shuffledUnique14WithoutSolutionLetters
        .addAll(solutionWord.characters.map((e) => LetterBoxData.fieldPick(e)));
    shuffledUnique14WithoutSolutionLetters.shuffle(random);

    assert(
        solutionWord.characters.every((element) =>
            shuffledUnique14WithoutSolutionLetters
                .map((e) => e.letter)
                .contains(element)),
        "Field does not contain all required solution letters.");

    return shuffledUnique14WithoutSolutionLetters;
  }

  List<String> getAvailableLetters() {
    return field
        .where((element) => element.state == LetterBoxState.fieldPick)
        .map((e) => e.letter)
        .toList();
  }

  List<String> getAllPickableLetters() {
    return (solution + field)
        .where((element) =>
            element.state == LetterBoxState.fieldPick ||
            element.state == LetterBoxState.solutionPick)
        .map((e) => e.letter)
        .toList();
  }

  bool isRemoveLettersAvailable() {
    var allUsableLetters = (solution + field).where((element) =>
        element.state == LetterBoxState.solutionPick ||
        element.state == LetterBoxState.fieldPick);
    return allUsableLetters.length > word.length;
  }

  void remove3ArbitaryLetters() {
    var count = 3;
    final solutionLetters = word.split('');

    var allPickableLetters = (solution + field).where((element) =>
        element.state == LetterBoxState.fieldPick ||
        element.state == LetterBoxState.solutionPick);

    var solutionLettersCopy = List<String>.from(solutionLetters);
    final candidateLetters = allPickableLetters.where((letterBox) {
      if (solutionLettersCopy.contains(letterBox.letter)) {
        solutionLettersCopy.remove(letterBox.letter);
        return false;
      }
      return true;
    }).toList();

    if (candidateLetters.length < 3) {
      count = candidateLetters.length;
    }
    var lettersToRemove = candidateLetters.toList().sample(count, Random(1337));

    for (var element in lettersToRemove) {
      if (element.state == LetterBoxState.fieldPick) {
        element.state = LetterBoxState.removed;
      } else if (element.state == LetterBoxState.solutionPick) {
        final originalFieldIndex = element.originalFieldIndex;
        if (originalFieldIndex != null && originalFieldIndex < field.length) {
          field[originalFieldIndex].letter = element.letter;
          field[originalFieldIndex].state = LetterBoxState.removed;
          element.letter = '';
          element.state = LetterBoxState.solutionSlot;
          element.originalFieldIndex = null;
        }
      }
    }
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
      return true;
    } else {
      return false;
    }
  }

  void setLevelCompleted() {
    for (var element in solution) {
      element.state = LetterBoxState.locked;
    }
  }

  void reset() {
    solution = List.generate(
        word.length, (index) => LetterBoxData.solutionSlot(),
        growable: false);
    for (var element in solution) {
      element.state = LetterBoxState.solutionSlot;
    }
    field = getFieldLetters(solutionPick: word, disabledLettersCount: 0);
    for (var i = 0; i < field.length; i++) {
      field[i].originalFieldIndex = i;
    }
    notifyListeners();
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
