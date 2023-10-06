import 'package:flutter/material.dart';
import 'package:operation_hermes/game/letter_box.dart';
import 'package:operation_hermes/game/letter_box_state.dart';
import 'package:operation_hermes/game/puzzle.dart';

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
      print(_solutionStack);
      print(_chooseStack);
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
      print(_solutionStack);
      print(_chooseStack);
      return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  for (final (i, letterData) in _solutionStack.indexed)
                    Flexible(
                      child: LetterBox(
                        callback: (data) {
                          return (data.state == LetterBoxState.placed)
                              ? _handleSlotLetterTouch(data)
                              : false;
                        },
                        data: letterData,
                      ),
                    ),
                ]),
                Puzzle(picturePath: widget.picture),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                        flex: 1,
                        child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                            ])),
                    Expanded(
                      flex: 3,
                      child: Column(
                        children: List.generate(
                          4,
                          (rowIndex) => Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(
                              4,
                              (columnIndex) {
                                var index = rowIndex * 4 + columnIndex;
                                var letterData = _chooseStack[index];
                                return Flexible(
                                  child: LetterBox(
                                    callback: (data) {
                                      return (data.state == LetterBoxState.pick)
                                          ? _handlePickLetterTouch(data)
                                          : false;
                                    },
                                    data: letterData,
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                    const Expanded(
                        flex: 1,
                        child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              ColoredBox(color: Colors.red),
                              ColoredBox(color: Colors.green),
                              ColoredBox(color: Colors.blue),
                            ])),
                  ],
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}
