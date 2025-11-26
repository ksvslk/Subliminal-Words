import 'package:flutter/material.dart';
import 'package:operation_hermes/ui/freud_dialog.dart';
import 'package:operation_hermes/ui/game_field.dart';
import 'package:operation_hermes/ui/hint_bar.dart';
import 'package:operation_hermes/change_notifier/level_model.dart';
import 'package:operation_hermes/ui/puzzle.dart';
import 'package:operation_hermes/menu/top_bar.dart';
import 'package:provider/provider.dart';

class GameFieldScreen extends StatefulWidget {
  const GameFieldScreen({super.key});

  @override
  State<GameFieldScreen> createState() => _GameFieldScreenState();
}

class _GameFieldScreenState extends State<GameFieldScreen> {
  bool _isInitializing = true;

  @override
  void initState() {
    super.initState();
    context.read<LevelModel>().initialize().then((_) {
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {

    if (_isInitializing) {
      return const Center(child: CircularProgressIndicator());
    }

    return Consumer<LevelModel>(
      builder: (context, levelModel, child) {
        return SafeArea(
          child: Stack(
            children: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Flexible(flex: 1, child: TopBar()),
                      Flexible(flex: 8, child: Puzzle()),
                      Flexible(
                          flex: 3,
                          child: AnimatedOpacity(
                            opacity: levelModel.isLevelReady ? 1.0 : 0.0,
                            duration: const Duration(milliseconds: 400),
                            child: GameField(),
                          )),
                      Flexible(
                          flex: 1,
                          child: HintBar()),
                    ],
                  ),
                ),
              ),
              const FreudDialog(),
            ],
          ),
        );
      },
    );
  }
}
