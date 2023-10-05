import 'dart:math';

import 'package:flutter/material.dart';
import 'package:operation_hermes/game/letter_box.dart';
import 'package:operation_hermes/game/letter_box_state.dart';
import 'package:operation_hermes/game/puzzle.dart';

class GameField extends StatefulWidget {
  const GameField(
      {super.key,
      required this.word,
      required this.picture,
      this.solution = const []});

  final String word;
  final String picture;
  final List solution;

  //TODO: chars in place; chars count removed (from selection)

  @override
  State<GameField> createState() => _GameFieldState();
}

class _GameFieldState extends State<GameField> {
  final List random21Letters = List.generate(21, (index) => randomLetter());

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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,children: [
                    for (var char in widget.word.characters)
                      Flexible(child: LetterBox(letter: char))
                  ]),
                  Puzzle(picturePath: widget.picture),
                  Column(
                    children: List.generate(
                      3,
                      (_) => Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          7,
                          (_) => Flexible(child: LetterBox(
                              letter: random21Letters.removeLast(),
                              state: LetterBoxState.letter,
                              callback: () => grow(context))),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
    );
  }
}

String randomLetter() {
  const letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  final random = Random();
  return letters[random.nextInt(letters.length)];
}


void grow(context) {
     print("IT WORKED!");
}