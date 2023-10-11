import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:operation_hermes/audio/audio_controller.dart';
import 'package:operation_hermes/audio/sounds.dart';
import 'package:operation_hermes/game/letter_box.dart';
import 'package:operation_hermes/game/letter_box_data.dart';
import 'package:operation_hermes/game/letter_box_state.dart';
import 'package:operation_hermes/game/level_model.dart';
import 'package:operation_hermes/game/nice_button.dart';
import 'package:operation_hermes/game/puzzle.dart';
import 'package:operation_hermes/settings/settings.dart';
import 'package:provider/provider.dart';

class GameField extends StatelessWidget {
  const GameField({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final levelModel = context.read<LevelModel>();
    final audioController = context.read<AudioController>();

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                    onPressed: () {
                      settings.toggleMusicOn();
                    },
                    icon: const Icon(Icons.music_note)),
                Puzzle(picturePath: levelModel.picturePath),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  for (final (i, _) in levelModel.solution.indexed)
                    Flexible(
                      child: ChangeNotifierProvider.value(
                        value: levelModel.solution[i],
                        child: Consumer<LetterBoxData>(
                          builder: (context, data, child) {
                            return GestureDetector(
                              onTap: () {
                                if (data.state == LetterBoxState.solutionPick) {
                                  audioController.playSfx(SfxType.freeLetter);
                                  levelModel.removeLetter(i, data);
                                }
                              },
                              child: LetterBox(
                                key: ValueKey('solution-$i'),
                                data: data,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                ]),
                const Divider(),
                Column(
                  children: List.generate(
                    2,
                    (rowIndex) => Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        7,
                        (columnIndex) {
                          var index = rowIndex * 7 + columnIndex;
                          return Flexible(
                            child: ChangeNotifierProvider.value(
                              value: levelModel.field[index],
                              child: Consumer<LetterBoxData>(
                                builder: (context, data, child) {
                                  return GestureDetector(
                                    onTap: () {
                                      if (!levelModel.levelComplete && data.state ==
                                              LetterBoxState.fieldPick &&
                                          !levelModel.isLastLetter()) {
                                        HapticFeedback.selectionClick();
                                        audioController
                                            .playSfx(SfxType.pickLetter);
                                        levelModel.putLetter(index, data);
                                        var result = levelModel.checkForWin();
                                        if (result) {
                                          HapticFeedback.mediumImpact();
                                          audioController.playSfx(SfxType.win);
                                        }
                                      }
                                    },
                                    child: LetterBox(
                                      key: ValueKey('field-$index'),
                                      data: data,
                                    ),
                                  );
                                },
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(child: NiceButton(buttonText: "Pinch")),
                    Flexible(child: NiceButton(buttonText: "Pinch")),
                    Flexible(child: NiceButton(buttonText: "Pinch")),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
