import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:operation_hermes/audio/audio_controller.dart';
import 'package:operation_hermes/audio/sounds.dart';
import 'package:operation_hermes/game/filled_letter_painter.dart';
import 'package:operation_hermes/game/model/level_model.dart';
import 'package:operation_hermes/game/model/picture_model.dart';
import 'package:operation_hermes/game/svg_letter.dart';
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
      return GestureDetector(
        onTap: levelModel.levelCompleted
            ? () {
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
                    int getDurationAndSetLettersInitialized(
                        SvgLetter svgLetter) {
                      if (svgLetter.initialLoad) {
                        svgLetter.initialLoad = false;
                        return 0;
                      } else {
                        return 2000;
                      }
                    }

                    final isDarkMode =
                        MediaQuery.of(context).platformBrightness ==
                            Brightness.dark;
                    final firstColor = isDarkMode
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.inversePrimary;
                    final secondColor = isDarkMode
                        ? Theme.of(context).colorScheme.inverseSurface
                        : Theme.of(context).colorScheme.surface;
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
                                child: Image.asset(
                                  model.picturePath,
                                  fit: BoxFit.contain,
                                  gaplessPlayback: true,
                                ),
                              ),
                              ...model.highlightLetters.map((svgLetter) {
                                return AnimatedOpacity(
                                  duration: Duration(
                                      milliseconds:
                                          getDurationAndSetLettersInitialized(
                                              svgLetter)),
                                  opacity: (svgLetter.show) ? 1.0 : 0.0,
                                  curve: Curves.fastOutSlowIn,
                                  onEnd: () {
                                    if (svgLetter.show &&
                                        !levelModel.levelCompleted) {
                                      model.hideLetter(svgLetter.letter);
                                    }
                                  },
                                  child: CustomPaint(
                                    painter: FilledLetterPainter(
                                        path: parseSvgPathData(svgLetter.path),
                                        firstColor: firstColor,
                                        secondColor: secondColor),
                                    child: const AspectRatio(
                                      aspectRatio: 1 / 1,
                                    ),
                                  ),
                                );
                              }).toList(),
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
                              IconButton.filled(
                                visualDensity: VisualDensity.comfortable,
                                style: IconButton.styleFrom(
                                    backgroundColor: Theme.of(context)
                                        .colorScheme
                                        .background
                                        .withOpacity(0.25)),
                                icon: Icon(
                                  Icons.zoom_out,
                                  color:
                                      pictureModel.scale <= pictureModel.minZoom
                                          ? null
                                          : Theme.of(context)
                                              .colorScheme
                                              .onBackground,
                                ),
                                onPressed:
                                    pictureModel.scale <= pictureModel.minZoom
                                        ? null
                                        : () {
                                            pictureModel.setScaleDown();
                                            audioController
                                                .playSfx(SfxType.zoomOut);
                                          },
                              ),
                              IconButton.filled(
                                visualDensity: VisualDensity.comfortable,
                                style: IconButton.styleFrom(
                                    backgroundColor: Theme.of(context)
                                        .colorScheme
                                        .background
                                        .withOpacity(0.25)),
                                icon: Icon(
                                  Icons.zoom_in,
                                  color:
                                      pictureModel.scale >= pictureModel.maxZoom
                                          ? null
                                          : Theme.of(context)
                                              .colorScheme
                                              .onBackground,
                                ),
                                onPressed: pictureModel.scale >=
                                        pictureModel.maxZoom
                                    ? null
                                    : () {
                                        pictureModel.setScaleUp();
                                        audioController.playSfx(SfxType.zoomIn);
                                      },
                              ),
                              IconButton.filled(
                                visualDensity: VisualDensity.comfortable,
                                style: IconButton.styleFrom(
                                    backgroundColor: Theme.of(context)
                                        .colorScheme
                                        .background
                                        .withOpacity(0.25)),
                                icon: Icon(
                                  Icons.rotate_90_degrees_cw,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onBackground,
                                ),
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
