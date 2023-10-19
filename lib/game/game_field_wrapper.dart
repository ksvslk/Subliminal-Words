import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:operation_hermes/game/game_field.dart';
import 'package:operation_hermes/game/model/level_model.dart';
import 'package:provider/provider.dart';

class GameFieldWrapper extends StatelessWidget {
  const GameFieldWrapper({super.key});
  static final _log = Logger('GameFieldWrapper');

  @override
  Widget build(BuildContext context) {
    final levelModel = context.read<LevelModel>();
    return FutureBuilder(
        future: levelModel.initialize(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            return const GameField();
          } else {
            return const Center(child: CircularProgressIndicator()); // show a loading indicator or some placeholder
          }
        });
  }
}
