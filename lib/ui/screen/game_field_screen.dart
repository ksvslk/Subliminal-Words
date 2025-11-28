import 'package:flutter/material.dart';
import 'package:operation_hermes/ui/freud_dialog.dart';
import 'package:operation_hermes/ui/game_field.dart';
import 'package:operation_hermes/ui/hint_bar.dart';
import 'package:operation_hermes/change_notifier/level_model.dart';
import 'package:operation_hermes/ui/puzzle.dart';
import 'package:operation_hermes/menu/top_bar.dart';
import 'package:operation_hermes/ui/random_tutorial_overlay.dart';
import 'package:provider/provider.dart';

class GameFieldScreen extends StatefulWidget {
  const GameFieldScreen({super.key});

  @override
  State<GameFieldScreen> createState() => _GameFieldScreenState();
}

class _GameFieldScreenState extends State<GameFieldScreen> {
  bool _isInitializing = true;

  // 1. Define keys here (local to this screen only)
  final GlobalKey _clueAreaKey = GlobalKey();
  final GlobalKey _playZoneKey = GlobalKey();

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
        
        // 2. Determine which text to show
        // You might need a check here like: levelModel.isMovieLevel
        String hintText = "Do You see the word?"; 
        
        return SafeArea(
          child: Stack(
            children: [
              // 3. Wrap the content in the Tutorial Overlay
              RandomTutorialOverlay(
                tutorialId: 'tutorial_intro_v1', 
                hintText: hintText,
                clueKey: _clueAreaKey,       // Target for Step 1
                playZoneKey: _playZoneKey,   // Target for Step 2
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Flexible(flex: 1, child: TopBar()),
                        
                        // 4. Wrap Puzzle in a Container with the key
                        // We do NOT modify the Puzzle widget itself.
                        Flexible(
                          flex: 8, 
                          child: Container(
                            key: _clueAreaKey, // The tutorial points here
                            child: const Puzzle(),
                          ),
                        ),
                        
                        Flexible(
                          flex: 3,
                          child: AnimatedOpacity(
                            opacity: levelModel.isLevelReady ? 1.0 : 0.0,
                            duration: const Duration(milliseconds: 400),
                            // 5. Wrap GameField in a Container with the key
                            child: Container(
                              key: _playZoneKey, // The finger flies around inside here
                              child: const GameField(),
                            ),
                          ),
                        ),
                            
                        Flexible(
                          flex: 1,
                          child: HintBar()
                        ),
                      ],
                    ),
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