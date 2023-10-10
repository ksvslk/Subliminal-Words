import 'package:flutter/material.dart';
import 'package:operation_hermes/game/game_field.dart';
import 'package:operation_hermes/game/level_model.dart';
import 'package:provider/provider.dart';

class GameFieldWrapper extends StatelessWidget {
  
  const GameFieldWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => LevelModel(),
      child: const GameField(),
    );
  }
}