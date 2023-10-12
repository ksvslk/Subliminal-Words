import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:operation_hermes/game/svg_letter.dart';
import 'package:path_drawing/path_drawing.dart';
import 'package:xml/xml.dart';

class Puzzle extends StatefulWidget {
  const Puzzle({super.key, required this.picturePath, required this.pinchEnabled});

  final String picturePath;
  final bool pinchEnabled;

  @override
  State<Puzzle> createState() => _PuzzleState();
}

class _PuzzleState extends State<Puzzle> {
  late Future<List<SvgLetter>> _svgLetters;

  @override
  void initState() {
    super.initState();
    _svgLetters = loadSvgLetters(svgImage: "assets/levels/1.svg");
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
        future: _svgLetters,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            return Flexible(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                      color: Theme.of(context).colorScheme.secondary, width: 2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Regular Image
                      InteractiveViewer(
                        panEnabled: false,
                        scaleEnabled: widget.pinchEnabled ? true : false,
                        maxScale: 1.0,
                        minScale: 0.2,
                        boundaryMargin: const EdgeInsets.all(256),
                        child: 
                      Image.asset(
                        widget.picturePath,
                        fit: BoxFit.fill,
                      )),
                      // Lettered Image with Color Filter
                      /*
                      Stack(
                        children: [
                        for (final letter in snapshot.data!)
                          CustomPaint(
                            size: Size(512, 512),
                            painter: FilledPathPainter(
                              path: parseSvgPathData(letter.partPath),
                              color: Colors.blue.withOpacity(0.4),
                            ),
                            
                          ),
                      ])
                      */
                    ],
                  ),
              ),
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
    print(size);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
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
