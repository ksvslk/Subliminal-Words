import 'dart:math';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import 'package:operation_hermes/controller/firebase_service.dart';
import 'package:operation_hermes/data/sw_level.dart';
import 'package:xml/xml.dart';

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:operation_hermes/data/svg_letter.dart';
import 'package:operation_hermes/data/word_letter_style.dart';

class PictureModel with ChangeNotifier {
  static final _log = Logger('PictureModel');

  final maxZoom = 1.0;
  final minZoom = 0.1;
  final zoomStep = 0.1;
  final FirebaseService _firebaseService;

  double scale;
  int quarterTurn;
  int levelNr;
  String picturePath;
  String svgPath;
  List<SvgLetter> highlightLetters = [];
  bool isFactTypeLevel = false;
  bool isFactLevelComplete = false;
  Uint8List? puzzleImageBytes;
  double solutionOpacity = 0.0;
  Timer? _solutionAnimationTimer;
  bool _isFadingIn = true;

  PictureModel({
    required this.scale,
    required this.quarterTurn,
    required this.picturePath,
    required this.svgPath,
    required this.levelNr,
    required FirebaseService firebaseService,
  }) : _firebaseService = firebaseService;

  @override
  void dispose() {
    _solutionAnimationTimer?.cancel();
    super.dispose();
  }

  Future<void> initializePicture({required SWLevel level}) async {
    scale = 1.0;
    quarterTurn = 0;
    levelNr = level.nr;

    if (level.isBundled) {
      picturePath = level.puzzlePath;
      svgPath = level.solutionPath;
    } else {
      picturePath = await _firebaseService.getDownloadUrl(level.puzzlePath);
      svgPath = await _firebaseService.getDownloadUrl(level.solutionPath);
    }

    isFactTypeLevel = !level.isHighlightType;
    isFactLevelComplete = false;
    solutionOpacity = 0.0;
    _isFadingIn = true;
    _solutionAnimationTimer?.cancel();
    _solutionAnimationTimer = null;

    try {
      puzzleImageBytes = await _loadPuzzleImageBytes(picturePath);
    } catch (e) {
      _log.severe('Failed to load puzzle image bytes for display/sharing', e);
      puzzleImageBytes = null;
    }

    if (level.isHighlightType) {
      highlightLetters = await _loadSvgLetters(svgPath: svgPath);
    } else {
      highlightLetters = [];
    }
    notifyListeners();
  }

  Future<Uint8List> _loadPuzzleImageBytes(String path) async {
    if (path.isEmpty) return Uint8List(0);

    if (path.startsWith('http')) {
      final response = await http.get(Uri.parse(path));
      if (response.statusCode == 200) {
        return response.bodyBytes;
      } else {
        throw Exception('Failed to download image: ${response.statusCode}');
      }
    } else {
      final byteData = await rootBundle.load(path);
      return byteData.buffer.asUint8List();
    }
  }

  Future<List<SvgLetter>> _loadSvgLetters({required String svgPath}) async {
    if (svgPath.isEmpty) return [];

    String svgString;
    if (svgPath.startsWith('http')) {
      final response = await http.get(Uri.parse(svgPath));
      svgString = response.body;
    } else {
      svgString = await rootBundle.loadString(svgPath);
    }
    return _parseSvg(svgString);
  }

  void setLevelComplete() {
    if (isFactTypeLevel) {
      isFactLevelComplete = true;
      notifyListeners();
    } else {
      for (var element in highlightLetters) {
        element.show = true;
      }
      notifyListeners();
    }
  }

  void beginSolutionAnimation() {
    if (isFactLevelComplete && _solutionAnimationTimer == null) {
      _startSolutionAnimationLoop();
    }
  }

  void _startSolutionAnimationLoop() {
    _solutionAnimationTimer?.cancel();

    const oneWayDuration = Duration(milliseconds: 3000);
    const animationCurve = Curves.easeIn;
    const frameDuration = Duration(milliseconds: 16); // ~60 FPS
    final totalFrames =
        oneWayDuration.inMilliseconds / frameDuration.inMilliseconds;
    final step = 1.0 / totalFrames;
    double progress = 0.0;

    _solutionAnimationTimer = Timer.periodic(frameDuration, (timer) {
      progress += step;
      if (progress > 1.0) {
        progress = 0.0;
        _isFadingIn = !_isFadingIn;
      }

      final curvedProgress = animationCurve.transform(progress);

      if (_isFadingIn) {
        solutionOpacity = curvedProgress;
      } else {
        solutionOpacity = 1.0 - curvedProgress;
      }
      notifyListeners();
    });
  }

  void setScaleDown() {
    var newScale = (scale - zoomStep);
    newScale = double.parse((newScale).toStringAsFixed(1));
    scale = newScale <= minZoom ? minZoom : newScale;
    notifyListeners();
  }

  void setScaleUp() {
    var newScale = (scale + zoomStep);
    newScale = double.parse((newScale).toStringAsFixed(1));
    scale = newScale >= maxZoom ? maxZoom : newScale;
    notifyListeners();
  }

  void setNextQuarterTurn() {
    quarterTurn =
        quarterTurn == 3 ? quarterTurn = 0 : quarterTurn = quarterTurn + 1;
    notifyListeners();
  }

  void highlightLetter(List<String> availableLetters) {
    if (highlightLetters.isEmpty) {
      return;
    }

    var allHintsGiven =
        highlightLetters.every((element) => element.hintGiven == true);

    if (allHintsGiven) {
      for (var element in highlightLetters) {
        element.hintGiven = false;
      }
    }
    List<int> candidateIndices = highlightLetters
        .asMap()
        .entries
        .where((entry) =>
            entry.value.hintGiven == false &&
            entry.value.show == false &&
            availableLetters.contains(entry.value.letter.toUpperCase()))
        .map((entry) => entry.key)
        .toList();

    if (candidateIndices.isEmpty) {
      return;
    }

    final letterIndexToHighlight =
        candidateIndices[Random().nextInt(candidateIndices.length)];
    highlightLetters[letterIndexToHighlight].show = true;
    highlightLetters[letterIndexToHighlight].hintGiven = true;
    notifyListeners();
  }

  void hideLetter(String letter) {
    int index = highlightLetters.indexWhere(
        (item) => item.letter.toUpperCase() == letter.toUpperCase());
    if (index != -1) {
      highlightLetters[index].show = false;
      notifyListeners();
    }
  }

  List<SvgLetter> _parseSvg(String svgString) {
    final List<SvgLetter> letters = [];
    XmlDocument document = XmlDocument.parse(svgString);
    final allPaths = document.findAllElements('path');
    for (var element in allPaths) {
      final path = element.getAttribute('d');
      final letter = (element.getAttribute('aria-label') ??
              element.getAttribute('id') ??
              '')
          .trim();
      if (letter.isNotEmpty && path != null) {
        final svgLetter = SvgLetter(path: path, letter: letter);
        if (letter.length <= 3) {
          letters.add(svgLetter);
        }
      }
    }

    final allText = document.findAllElements('text');
    for (var element in allText) {
      final text = element.innerText.trim();
      final letter = (element.getAttribute('aria-label') ?? text).trim();
      if (letter.isEmpty) {
        continue;
      }

      final x = double.tryParse(
        element.getAttribute('data-x') ?? element.getAttribute('x') ?? '',
      );
      final y = double.tryParse(
        element.getAttribute('data-y') ?? element.getAttribute('y') ?? '',
      );
      final fontSize = double.tryParse(
        element.getAttribute('font-size') ??
            element.getAttribute('data-font-size') ??
            '',
      );
      if (x == null || y == null || fontSize == null) {
        continue;
      }

      final svgLetter = SvgLetter(
        path: '',
        letter: letter,
        text: text,
        x: x,
        y: y,
        fontSize: fontSize,
        fontWeightValue: normalizeWordLetterWeightValue(
          int.tryParse(
                element.getAttribute('font-weight') ??
                    element.getAttribute('data-font-weight') ??
                    '',
              ) ??
              kDefaultWordLetterWeightValue,
        ),
        rotationDegrees: _rotationFromTransform(
          element.getAttribute('transform'),
          element.getAttribute('data-rotation'),
        ),
        scaleX:
            double.tryParse(element.getAttribute('data-scale-x') ?? '') ?? 1,
        scaleY:
            double.tryParse(element.getAttribute('data-scale-y') ?? '') ?? 1,
        skewXDegrees:
            double.tryParse(element.getAttribute('data-skew-x') ?? '') ?? 0,
        skewYDegrees:
            double.tryParse(element.getAttribute('data-skew-y') ?? '') ?? 0,
        opacity:
            double.tryParse(element.getAttribute('data-opacity') ?? '') ?? 1,
      );
      if (letter.length <= 3) {
        letters.add(svgLetter);
      }
    }
    return letters;
  }

  double _rotationFromTransform(String? transform, String? rotationAttr) {
    final parsedRotation = double.tryParse(rotationAttr ?? '');
    if (parsedRotation != null) {
      return parsedRotation;
    }

    final normalized = transform ?? '';
    final match = RegExp(r'rotate\(([-\d.]+)').firstMatch(normalized);
    if (match == null) {
      return 0;
    }

    return double.tryParse(match.group(1) ?? '') ?? 0;
  }

  void reset() {
    scale = 1.0;
    quarterTurn = 0;
    notifyListeners();
  }
}
