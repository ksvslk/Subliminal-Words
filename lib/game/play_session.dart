import 'dart:math';

import 'package:flutter/material.dart';
import 'package:operation_hermes/game/game_field.dart';
import 'package:operation_hermes/game/letter_box_state.dart';

String randomLetter() {
  const letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  final random = Random();
  return letters[random.nextInt(letters.length)];
}

class PlaySession extends StatefulWidget {
  const PlaySession({super.key});

  final bool levelCompleted = false;

  @override
  State<PlaySession> createState() => _PlaySessionState();
}

class _PlaySessionState extends State<PlaySession> {
  final initialQueue = List.generate(7, (index) => (index:index, letter: LetterBoxState.slot.name, state: LetterBoxState.slot), growable: false);
  final random21Letters = List.generate(14, (index) => (index: index, letter: randomLetter(), state: LetterBoxState.pick), growable: false);

  @override
  Widget build(BuildContext context) {
    return GameField(
      word: 'TEREKST',
      picture: 'assets/levels/1.jpg',
      solutionStack: initialQueue,
      chooseStack: random21Letters,
    );
  }
}
