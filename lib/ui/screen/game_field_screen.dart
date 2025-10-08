import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:operation_hermes/ui/freud_dialog.dart';
import 'package:operation_hermes/ui/game_field.dart';
import 'package:operation_hermes/ui/hint_bar.dart';
import 'package:operation_hermes/change_notifier/level_model.dart';
import 'package:operation_hermes/ui/puzzle.dart';
import 'package:operation_hermes/menu/top_bar.dart';
import 'package:provider/provider.dart';

class GameFieldScreen extends StatelessWidget {
  const GameFieldScreen({super.key});
  static final _log = Logger('GameFieldWrapper');

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: Provider.of<LevelModel>(context, listen: false).initialize(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          return const SafeArea(
              child: Stack(
            children: [
              Center(
                child: Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Flexible(flex: 1, child: TopBar()),
                      Flexible(flex: 8, child: Puzzle()),
                      Flexible(flex: 3, child: GameField()),
                      Flexible(flex: 1, child: HintBar()),
                    ],
                  ),
                ),
              ),
              FreudDialog(),
            ],
          ));
        } else if (snapshot.hasError) {
          return ErrorWidget(snapshot.error!);
        } else {
          return const Center(child: CircularProgressIndicator());
        }
      },
    );
  }
}
