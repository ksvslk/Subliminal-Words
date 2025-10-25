import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
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
  static final _log = Logger('GameFieldWrapper');
  bool _isInitializing = true;

  @override
  void initState() {
    super.initState();
    // Start initialization when the widget is first created.
    // We use `context.read` because we don't need to listen for changes here.
    context.read<LevelModel>().initialize().then((_) {
      // Once initialization is complete, update the state to stop showing
      // the loading indicator.
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // While initializing, show a loading spinner.
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
                      // The Puzzle widget already handles its own shimmer state internally.
                      Flexible(flex: 8, child: Puzzle()),
                      Flexible(
                          flex: 3,
                          // The GameField widget now handles its own loading state internally,
                          // preventing any layout shift.
                          child: AnimatedOpacity(
                            opacity: levelModel.isLevelReady ? 1.0 : 0.0,
                            duration: const Duration(milliseconds: 400),
                            child: GameField(),
                          )),
                      Flexible(
                          flex: 1,
                          // The HintBar also handles its own loading state.
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
