import 'dart:math';

import 'package:dotted_border/dotted_border.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:operation_hermes/audio/audio_controller.dart';
import 'package:operation_hermes/audio/sounds.dart';
import 'package:operation_hermes/game/level_model.dart';
import 'package:operation_hermes/game/svg_letter.dart';
import 'package:path_drawing/path_drawing.dart';
import 'package:provider/provider.dart';
import 'package:xml/xml.dart';
import 'package:vector_math/vector_math_64.dart' as vec3;

class Puzzle extends StatefulWidget {
  const Puzzle(
      {super.key,
      required this.picturePath});

  final String picturePath;

  @override
  State<Puzzle> createState() => _PuzzleState();
}

class _PuzzleState extends State<Puzzle> {
  late Future<List<SvgLetter>> _svgLetters;
  List<SvgLetter> _letters = [];

  final maxZoom = 1.0;
  final minZoom = 0.1;
  final zoomStep = 0.1;
  double _scale = 1.0;
  int _currentQuarterTurn = 0;

  @override
  void initState() {
    super.initState();
    _svgLetters = loadSvgLetters(svgImage: "assets/levels/1.svg");
  }

  @override
  Widget build(BuildContext context) {
    print("Build puzzle picture all");
    final levelModel = context.watch<LevelModel>();
    final audioController = context.read<AudioController>();
    
    return FutureBuilder(
        future: _svgLetters,
        builder: (context, snapshot) {
         _letters = snapshot.data!;
          if (snapshot.connectionState == ConnectionState.done) {
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
                        color: Theme.of(context).colorScheme.secondary,
                        width: 2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: RotatedBox(
                    quarterTurns: _currentQuarterTurn,
                    child: AnimatedContainer(
                      foregroundDecoration: BoxDecoration(
                          border: Border.all(
                              width: _scale < 1.0
                                  ? double.parse(
                                      (1.5 / _scale).toStringAsFixed(1))
                                  : 0.0,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant)),
                      duration: const Duration(milliseconds: 150),
                      curve: Curves.easeOutBack,
                      transformAlignment: Alignment.center,
                      transform: Matrix4.diagonal3(
                          vec3.Vector3(_scale, _scale, _scale)),
                      child: Stack(
                        children: [
                          Image.asset(
                            widget.picturePath,
                            fit: BoxFit.fill,
                          ),
                          ..._letters
                              .map((letter) => AnimatedOpacity(
                                  duration: const Duration(milliseconds: 200),
                                  opacity: levelModel.letterToShow == letter.name ? 1.0 : 0.0,
                                  onEnd: () {
                                    levelModel.letterToShow = '';
                                  },
                                  child: CustomPaint(
                                    painter: FilledPathPainter(
                                      path: parseSvgPathData(letter.partPath),
                                      color: Colors.red.withOpacity(0.5),
                                    ),
                                  )))
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
                                          _scale = newScale <= minZoom
                                              ? minZoom
                                              : newScale;
                                        });
                                        audioController
                                            .playSfx(SfxType.zoomOut);
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
                                          _scale = newScale >= maxZoom
                                              ? maxZoom
                                              : newScale;
                                        });
                                        audioController.playSfx(SfxType.zoomIn);
                                      },
                              ),
                              IconButton.filledTonal(
                                icon: const Icon(Icons.rotate_90_degrees_cw),
                                onPressed: () {
                                  audioController.playSfx(SfxType.rotate);
                                  setState(() {
                                    _currentQuarterTurn =
                                        _currentQuarterTurn == 3
                                            ? _currentQuarterTurn = 0
                                            : _currentQuarterTurn =
                                                _currentQuarterTurn + 1;
                                  });
                                },
                              ),
                            ],
                          )
                        : null)
              ],
            );
          } else {
            return const CircularProgressIndicator();
          }
        });
  }
}

class FilledPathPainter extends CustomPainter {
  const FilledPathPainter({
    required this.path,
    required this.color,
  });

  final Path path;
  final Color color;

  @override
  bool shouldRepaint(FilledPathPainter oldDelegate) =>
      oldDelegate.path != path || oldDelegate.color != color;

  @override
  void paint(Canvas canvas, Size size) {
    // Obtain the bounding box of the path
    final Rect pathBounds = path.getBounds();

    // canvas.scale(0.5, 0.5);
    print(canvas);
    print(size);

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 4.0
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool hitTest(Offset position) => path.contains(position);
}

Future<List<SvgLetter>> loadSvgLetters({required String svgImage}) async {
  List<SvgLetter> maps = [];
  String generalString = await rootBundle.loadString(svgImage);
  XmlDocument document = XmlDocument.parse(generalString);
  final paths = document.findAllElements('path');
  for (var element in paths) {
    String partId = element.getAttribute('id').toString();
    String partPath = element.getAttribute('d').toString();
    String name = element.getAttribute('inkscape:label').toString();
    var svgLetter =
        SvgLetter(partPathSvg: partPath, nameSvg: name, partIdSvg: partId);
    maps.add(svgLetter);
    print("Added: ${svgLetter.partId}");
  }
  return maps;
}
