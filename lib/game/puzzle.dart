import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:operation_hermes/audio/audio_controller.dart';
import 'package:operation_hermes/audio/sounds.dart';
import 'package:operation_hermes/game/filled_letter_painter.dart';
import 'package:operation_hermes/game/model/level_model.dart';
import 'package:operation_hermes/game/model/picture_model.dart';
import 'package:path_drawing/path_drawing.dart';
import 'package:provider/provider.dart';
import 'package:vector_math/vector_math_64.dart' as vec3;

class Puzzle extends StatelessWidget {
  const Puzzle({super.key});

  static final _log = Logger('_PuzzleState');

  @override
  Widget build(BuildContext context) {
    final audioController = context.read<AudioController>();

    return Consumer<LevelModel>(builder: (context, levelModel, child) {
      _log.info(() =>
          'Build puzzle. Consumer of LevelModel. Level complete: ${levelModel.pictureModel.picturePath}');
      return GestureDetector(
        onTap: levelModel.levelCompleted
            ? () {
                _log.info(Level.INFO, "TER!!");
                levelModel.nextLevel();
              }
            : null,
        child: AspectRatio(
          aspectRatio: 1,
          child: Stack(
            fit: StackFit
                .expand, // This ensures the stack takes the full size of its parent
            children: <Widget>[
              Container(
                decoration: BoxDecoration(
                  image: DecorationImage(
                      image: const AssetImage(
                          'assets/other/grid.png'), // Replace with your image's path
                      repeat: ImageRepeat.repeat,
                      colorFilter: ColorFilter.mode(
                          Theme.of(context).colorScheme.secondaryContainer,
                          BlendMode.modulate)),
                  color: Theme.of(context)
                      .colorScheme
                      .secondaryContainer
                      .withOpacity(0.25),
                  border: Border.all(
                      color: Theme.of(context).colorScheme.secondary, width: 1),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              // The image
              ChangeNotifierProvider<PictureModel>.value(
                value: levelModel.pictureModel,
                child: Consumer<PictureModel>(
                  builder: (context, model, child) {
                    _log.log(Level.INFO, "now with letters: ${model.highlightLetters.first.letter}");

                    return RotatedBox(
                      quarterTurns: model.quarterTurn,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                          transformAlignment: Alignment.center,
                          transform: Matrix4.diagonal3(vec3.Vector3(
                              model.scale, model.scale, model.scale)),
                          child: Stack(
                            fit: StackFit.expand,
                            alignment: Alignment.center,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child:
                                 Image.asset(
                                  model.picturePath,
                                  fit: BoxFit.contain,
                                  gaplessPlayback: true,
                                ),
                              ),
                              ...model.highlightLetters
                                  .map(
                                    (svgLetter) => AnimatedOpacity(
                                      duration: Duration(
                                          milliseconds: svgLetter.show ? 1750 : 0),
                                      opacity: (svgLetter.show)
                                          ? 1.0
                                          : 0.0,
                                      curve: Curves.fastOutSlowIn,
                                      onEnd: () {
                                      
                                        _log.info(() =>
                                            'Ending svg letter animation for - ${svgLetter.letter} with show - ${svgLetter.show}');
                                        if (svgLetter.show) {
                                          model.hideLetter(svgLetter.letter);
                                          _log.info(() =>
                                              'hideLetter - ${svgLetter.letter}}');
                                        }
                                      },
                                      child: CustomPaint(
                                        painter: FilledLetterPainter(
                                            path: parseSvgPathData(
                                                svgLetter.path),
                                            letterOutlineColor:
                                                Theme.of(context)
                                                    .colorScheme
                                                    .primary),
                                        child: AspectRatio(
                                          aspectRatio: 1 / 1,
                                          child: Container(
                                            color: Colors
                                                .transparent, // Or any other color to visualize it
                                          ),
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ],
                          )
                          // PROBLEM CHILD ABOVE
                          ),
                    );
                  },
                ),
              ),

              Container(
                decoration: BoxDecoration(
                  border: Border.all(
                      strokeAlign: BorderSide.strokeAlignCenter,
                      color: Theme.of(context).colorScheme.secondary,
                      width: 1),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              // Manipulation buttons, positioned bottom right
              levelModel.manipulationEnabled
                  ? ChangeNotifierProvider<PictureModel>.value(
                      value: levelModel.pictureModel,
                      child: Consumer<PictureModel>(
                          builder: (context, pictureModel, child) {
                        return Positioned(
                          bottom: 4,
                          right: 4,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              IconButton.filledTonal(
                                icon: const Icon(Icons.zoom_out),
                                onPressed:
                                    pictureModel.scale <= pictureModel.minZoom
                                        ? null
                                        : () {
                                            pictureModel.setScaleDown();
                                            audioController
                                                .playSfx(SfxType.zoomOut);
                                          },
                              ),
                              IconButton.filledTonal(
                                icon: const Icon(Icons.zoom_in),
                                onPressed: pictureModel.scale >=
                                        pictureModel.maxZoom
                                    ? null
                                    : () {
                                        pictureModel.setScaleUp();
                                        audioController.playSfx(SfxType.zoomIn);
                                      },
                              ),
                              IconButton.filledTonal(
                                icon: const Icon(Icons.rotate_90_degrees_cw),
                                onPressed: () {
                                  audioController.playSfx(SfxType.rotate);
                                  pictureModel.setNextQuarterTurn();
                                },
                              )
                            ],
                          ),
                        );
                      }),
                    )
                  : const SizedBox.shrink(),
            ],
          ),
        ),
      );
    });
  }
}
