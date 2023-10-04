import 'package:flutter/material.dart';
import 'package:operation_hermes/game/game_field.dart';

class PlaySession extends StatefulWidget {
  const PlaySession({super.key});

  final bool levelCompleted = false;

  @override
  State<PlaySession> createState() => _PlaySessionState();
}

class _PlaySessionState extends State<PlaySession> {
  @override
  Widget build(BuildContext context) {
    return const GameField(word: 'TEREKST', picture: 'assets/levels/1.jpg',);
  }
}