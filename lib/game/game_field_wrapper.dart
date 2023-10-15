import 'package:flutter/material.dart';
import 'package:operation_hermes/game/game_field.dart';
import 'package:operation_hermes/game/level_data.dart';
import 'package:operation_hermes/game/level_model.dart';
import 'package:operation_hermes/level/level_controller.dart';
import 'package:provider/provider.dart';

class GameFieldWrapper extends StatelessWidget {
  const GameFieldWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final levelController = context.watch<LevelController>();

    return ValueListenableBuilder<LevelData?>(
      valueListenable: levelController.currentLevel,
      builder: (context, levelData, _) {
        if (levelData == null) {
          return const Center(child: CircularProgressIndicator());
        } else {
          final levelModel = levelController.levelModel;
          return ChangeNotifierProvider<LevelModel>.value(
            value: levelModel!,
            child: const GameField(),
          );
        }
      },
    );
  }
}
