import 'dart:math';

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:operation_hermes/game/letter_box.dart';
import 'package:operation_hermes/game/letter_box_state.dart';
import 'package:operation_hermes/game/nice_button.dart';
import 'package:operation_hermes/game/puzzle.dart';
import 'package:operation_hermes/settings/settings.dart';
import 'package:provider/provider.dart';

class GameField extends StatefulWidget {
  const GameField(
      {super.key,
      required this.word,
      required this.picture,
      required this.solutionStack,
      required this.chooseStack});

  final String word;
  final String picture;
  final List<LetterData> solutionStack;
  final List<LetterData> chooseStack;

  //TODO: chars in place; chars count removed (from selection)

  @override
  State<GameField> createState() => _GameFieldState();
}

class _GameFieldState extends State<GameField> {
  late List<LetterData> _solutionStack;
  late List<LetterData> _chooseStack;

  @override
  void initState() {
    super.initState();
    _solutionStack = widget.solutionStack;
    _chooseStack = widget.chooseStack;
  }

  bool _handlePickLetterTouch(LetterData letterData) {
    var lastFreeSlot = _solutionStack
        .indexWhere((element) => element.state == LetterBoxState.slot);
    if (lastFreeSlot == -1) {
      return false;
    } else {
      setState(() {
        _solutionStack[lastFreeSlot] = (
          index: lastFreeSlot,
          letter: letterData.letter,
          state: LetterBoxState.placed
        );
        _chooseStack[letterData.index] = (
          index: letterData.index,
          letter: letterData.letter,
          state: LetterBoxState.chosen
        );
      });
      return true;
    }
  }

  bool _handleSlotLetterTouch(LetterData letterData) {
    var firstFreeSpot = _chooseStack
        .indexWhere((element) => element.state == LetterBoxState.chosen);
    if (firstFreeSpot == -1) {
      return false;
    } else {
      setState(() {
        _chooseStack[firstFreeSpot] = (
          index: firstFreeSpot,
          letter: letterData.letter,
          state: LetterBoxState.pick
        );
        _solutionStack[letterData.index] = (
          index: letterData.index,
          letter: letterData.letter,
          state: LetterBoxState.slot
        );
      });
      return true;
    }
  }

  bool _handleEmptySlotTouch() {
    var lastPlacedSlotLetter = _solutionStack
        .lastIndexWhere((element) => element.state == LetterBoxState.placed);

    var firstFreeSpot = _chooseStack
        .indexWhere((element) => element.state == LetterBoxState.chosen);

    if (lastPlacedSlotLetter == -1) {
      return false;
    } else {
      setState(() {
        _chooseStack[firstFreeSpot] = (
          index: firstFreeSpot,
          letter: _solutionStack[lastPlacedSlotLetter].letter,
          state: LetterBoxState.pick
        );
        _solutionStack[lastPlacedSlotLetter] = (
          index: lastPlacedSlotLetter,
          letter: "",
          state: LetterBoxState.slot
        );
      });
      return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                    onPressed: () {
                      settings.toggleMusicOn();
                    },
                    icon: const Icon(Icons.music_note)),
                Puzzle(picturePath: widget.picture),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  for (final (i, letterData) in _solutionStack.indexed)
                    Flexible(
                      child: LetterBox(
                        callback: (data) {
                          if (data.state == LetterBoxState.placed) {
                            return _handleSlotLetterTouch(data);
                          } else if (data.state == LetterBoxState.slot) {
                            return _handleEmptySlotTouch();
                          } else {
                            return false;
                          }
                        },
                        data: letterData,
                      ),
                    ),
                ]),
                Divider(),
                Column(
                  children: List.generate(
                    2,
                    (rowIndex) => Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        7,
                        (columnIndex) {
                          var index = rowIndex * 7 + columnIndex;
                          var letterData = _chooseStack[index];
                          return Flexible(
                              flex: 1,
                              child: LetterBox(
                                callback: (data) {
                                  return (data.state == LetterBoxState.pick)
                                      ? _handlePickLetterTouch(data)
                                      : false;
                                },
                                data: letterData,
                              ));
                        },
                      ),
                    ),
                  ),
                ),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(child: NiceButton(buttonText: "Pinch")),
                    Flexible(child: NiceButton(buttonText: "Pinch")),
                    Flexible(child: NiceButton(buttonText: "Pinch")),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
