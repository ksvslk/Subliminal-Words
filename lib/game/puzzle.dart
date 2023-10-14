import 'package:flutter/material.dart';
import 'package:operation_hermes/audio/audio_controller.dart';
import 'package:operation_hermes/audio/sounds.dart';
import 'package:operation_hermes/game/filled_letter_painter.dart';
import 'package:operation_hermes/game/level_model.dart';
import 'package:path_drawing/path_drawing.dart';
import 'package:provider/provider.dart';
import 'package:vector_math/vector_math_64.dart' as vec3;

class Puzzle extends StatefulWidget {
  const Puzzle({super.key, required this.picturePath});

  final String picturePath;

  @override
  State<Puzzle> createState() => _PuzzleState();
}

class _PuzzleState extends State<Puzzle> {
  final maxZoom = 1.0;
  final minZoom = 0.1;
  final zoomStep = 0.1;
  double _scale = 1.0;
  int _currentQuarterTurn = 0;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    print("Build puzzle picture all");
    final levelModel = context.watch<LevelModel>();
    final audioController = context.read<AudioController>();

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
          child: RotatedBox(
            quarterTurns: _currentQuarterTurn,
            child: AnimatedContainer(
              foregroundDecoration: BoxDecoration(
                  border: Border.all(
                      width: _scale < 1.0
                          ? double.parse((1.5 / _scale).toStringAsFixed(1))
                          : 0.0,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOutBack,
              transformAlignment: Alignment.center,
              transform:
                  Matrix4.diagonal3(vec3.Vector3(_scale, _scale, _scale)),
              child: Stack(
                children: [
                  Image.asset(
                    widget.picturePath,
                    fit: BoxFit.fill,
                  ),
                  ...levelModel.svgLetters
                      .map(
                        (svgLetter) => AnimatedOpacity(
                          duration: const Duration(milliseconds: 500),
                          opacity: svgLetter.show
                              ? 1.0
                              : 0.0,
                          child: CustomPaint(
                            painter: FilledLetterPainter(
                              path: parseSvgPathData(svgLetter.path),
                              color: Theme.of(context).colorScheme.primary.withOpacity(0.75),
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
          ),
        ),
        Container(
            padding: const EdgeInsets.all(8.0),
            child: levelModel.zoomAndRotateEnabled
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton.filledTonal(
                        icon: const Icon(Icons.zoom_out),
                        onPressed: _scale <= minZoom
                            ? null
                            : () {
                                setState(() {
                                  var newScale = (_scale - zoomStep);
                                  newScale = double.parse(
                                      (newScale).toStringAsFixed(1));
                                  _scale =
                                      newScale <= minZoom ? minZoom : newScale;
                                });
                                audioController.playSfx(SfxType.zoomOut);
                              },
                      ),
                      IconButton.filledTonal(
                        icon: const Icon(Icons.zoom_in),
                        onPressed: _scale >= maxZoom
                            ? null
                            : () {
                                setState(() {
                                  var newScale = (_scale + zoomStep);
                                  newScale = double.parse(
                                      (newScale).toStringAsFixed(1));
                                  _scale =
                                      newScale >= maxZoom ? maxZoom : newScale;
                                });
                                audioController.playSfx(SfxType.zoomIn);
                              },
                      ),
                      IconButton.filledTonal(
                        icon: const Icon(Icons.rotate_90_degrees_cw),
                        onPressed: () {
                          audioController.playSfx(SfxType.rotate);
                          setState(() {
                            _currentQuarterTurn = _currentQuarterTurn == 3
                                ? _currentQuarterTurn = 0
                                : _currentQuarterTurn = _currentQuarterTurn + 1;
                          });
                        },
                      ),
                    ],
                  )
                : null)
      ],
    );
  }
}
