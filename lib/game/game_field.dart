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
                Consumer<LevelModel>(builder: (context, model, child) {
                  return Puzzle(picturePath: model.picturePath);
                }),
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
                                      if (!levelModel.levelComplete &&
                                          data.state ==
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
                Consumer<LevelModel>(
                  builder: (context, model, child) {
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: NiceButton(
                              buttonText: model.removeLettersAvailable
                                  ? "Remove 3"
                                  : "-",
                              callback: () {
                                if (model.removeLettersAvailable) {
                                  audioController.playSfx(SfxType.wrong);
                                  levelModel.remove3ArbitaryLetters();
                                }
                              }),
                        ),
                        Flexible(
                          child: NiceButton(
                              buttonText: model.zoomAndRotateEnabled ? "-" : "Zoom + Rotate",
                              callback: () {
                                if (!model.zoomAndRotateEnabled) {
                                  audioController.playSfx(SfxType.rewardGiven);
                                  levelModel.activatePinch();
                                }
                              }),
                        ),
                        Flexible(
                            child: NiceButton(
                              buttonText: "Highlight", callback: () {
                              audioController.playSfx(SfxType.rewardGiven);
                              levelModel.highlightRandomLetter();
                            }
                            )),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}



class ZoomImageDemo extends StatefulWidget {
  @override
  _ZoomImageDemoState createState() => _ZoomImageDemoState();
}

class _ZoomImageDemoState extends State<ZoomImageDemo> {
  final TransformationController _controller = TransformationController();

  void _centerAndScaleOutImage() {
    // This scales the image out by a factor of 0.5 (half of its size)
    // and keeps it centered.
    _controller.value = Matrix4.identity()..scale(0.5);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('InteractiveViewer Demo'),
      ),
      body: Center(
        child: InteractiveViewer(
          transformationController: _controller,
          boundaryMargin: EdgeInsets.all(20.0),
          minScale: 0.1,
          maxScale: 2.0,
          child:   Image.asset(
                        'assets/levels/1.png',
                        fit: BoxFit.fill,
                      )),
        ),
      floatingActionButton: FloatingActionButton(
        onPressed: _centerAndScaleOutImage,
        child: Icon(Icons.zoom_out),
      ),
    );
  }
}