import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:operation_hermes/audio/audio_controller.dart';
import 'package:operation_hermes/audio/sounds.dart';
import 'package:operation_hermes/game/filled_letter_painter.dart';
import 'package:operation_hermes/game/model/hint_model.dart';
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
    _log.info(() => 'Build puzzle.');
    return Consumer<LevelModel>(builder: (context, levelModel, child) {
      _log.info(() => 'Build puzzle ALL ->.');
      return Stack(
        alignment: Alignment.bottomRight,
        children: [
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .secondaryContainer
                  .withOpacity(0.25),
              border: Border.all(
                  color: Theme.of(context).colorScheme.secondary, width: 2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Consumer<PictureModel>(builder: (context, model, child) {
              _log.info(() => 'Build puzzle RotatedBox.');
              return RotatedBox(
                quarterTurns: model.quarterTurn,
                child: AnimatedContainer(
                  foregroundDecoration: BoxDecoration(
                    border: Border.all(
                        width: model.scale < 1.0
                            ? double.parse(
                                (1.5 / model.scale).toStringAsFixed(1))
                            : 0.0,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeOutBack,
                  transformAlignment: Alignment.center,
                  transform: Matrix4.diagonal3(
                      vec3.Vector3(model.scale, model.scale, model.scale)),
                  child: Stack(
                    children: [
                      Image.asset(
                        model.picturePath,
                        fit: BoxFit.fill,
                      ),
                      ...model.highlightLetters
                          .map(
                            (svgLetter) => AnimatedOpacity(
                              duration: Duration(
                                  milliseconds: svgLetter.show ? 750 : 750),
                              opacity:
                                  svgLetter.show || levelModel.levelCompleted
                                      ? 1.0
                                      : 0.0,
                              curve: Curves.fastOutSlowIn,
                              onEnd: () {
                                _log.info(() =>
                                    'Ending svg letter animation for: ${svgLetter.letter} with show: ${svgLetter.show}');
                                if (svgLetter.show) {
                                  model.hideLetter(svgLetter.letter);
                                }
                              },
                              child: CustomPaint(
                                painter: FilledLetterPainter(
                                  path: parseSvgPathData(svgLetter.path),
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withOpacity(0.75),
                                ),
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
                  ),
                ),
              );
            }),
          ),
          ChangeNotifierProvider<HintModel>.value(
              value: levelModel.hintModel,
              child: Consumer<HintModel>(
                builder: (context, hintModel, child) {
                  _log.info(() => 'Build puzzle picture zoom buttons.');
                  return Container(
                      padding: const EdgeInsets.all(8.0),
                      child: hintModel.zoomRewarded
                          ? Consumer<PictureModel>(
                              builder: (context, pictureModel, child) {
                              _log.info(() =>
                                  'Build puzzle picture row of zoom buttons.');
                              return Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  IconButton.filledTonal(
                                    icon: const Icon(Icons.zoom_out),
                                    onPressed: pictureModel.scale <=
                                            pictureModel.minZoom
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
                                            audioController
                                                .playSfx(SfxType.zoomIn);
                                          },
                                  ),
                                  IconButton.filledTonal(
                                    icon:
                                        const Icon(Icons.rotate_90_degrees_cw),
                                    onPressed: () {
                                      audioController.playSfx(SfxType.rotate);
                                      pictureModel.setNextQuarterTurn();
                                    },
                                  ),
                                ],
                              );
                            })
                          : null);
                },
              )),
        ],
      );
    });
  }
}
