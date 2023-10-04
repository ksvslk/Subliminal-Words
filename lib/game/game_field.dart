import 'dart:math';

import 'package:flutter/material.dart';
import 'package:operation_hermes/game/letter_box.dart';
import 'package:operation_hermes/game/letter_box_state.dart';

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
    return MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    for (var char in widget.word.characters)
                      LetterBox(letter: char)
                  ]),
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: Image.asset(
                        widget.picture,
                        fit: BoxFit.scaleDown,
                      ),
                    ),
                  ),
                  Column(
                    children: List.generate(
                      3,
                      (_) => Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          7,
                          (_) => LetterBox(
                              letter: random21Letters.removeLast(),
                              state: LetterBoxState.letter,
                              callback: () => grow(context)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
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