import 'dart:io';
import 'dart:math';
import 'dart:async'; // Import for Timer
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import 'package:operation_hermes/controller/firebase_service.dart';
import 'package:operation_hermes/data/sw_level.dart';
import 'package:xml/xml.dart';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:operation_hermes/data/svg_letter.dart';

class PictureModel with ChangeNotifier {
  static final _log = Logger('PictureModel');

  final maxZoom = 1.0;
  final minZoom = 0.1;
  final zoomStep = 0.1;
  final FirebaseService _firebaseService; // Renamed to private

  double scale;
  int quarterTurn;
  int levelNr;
  String picturePath;
  String svgPath; // For fact levels, this holds the solution image path
  List<SvgLetter> highlightLetters = [];
  bool isFactTypeLevel = false; // Made public to be used by PictureWidget
  bool isFactLevelComplete = false; // New flag to indicate completion

  // Animation properties for solution image looping opacity
  double solutionOpacity = 0.0;
  Timer? _solutionAnimationTimer;
  bool _isFadingIn = true; // Controls the direction of the opacity animation

  PictureModel({
    required this.scale,
    required this.quarterTurn,
    required this.picturePath,
    required this.svgPath,
    required this.levelNr,
    required FirebaseService firebaseService, // Add firebaseService to constructor
  }) : _firebaseService = firebaseService {
    // Initialization is now handled by initializePicture to avoid race conditions.
  }

  @override
  void dispose() {
    _solutionAnimationTimer?.cancel(); // Cancel timer to prevent memory leaks
    super.dispose();
  }

  Future<void> initializePicture(
      {required SWLevel level}) async {
    scale = 1.0;
    quarterTurn = 0;
    this.levelNr = level.nr;

    // Determine if paths are local assets or remote URLs
    if (level.isBundled) {
      this.picturePath = level.puzzlePath;
      this.svgPath = level.solutionPath;
    } else {
      // Fetch remote URLs for non-bundled levels
      this.picturePath = await _firebaseService.getDownloadUrl(level.puzzlePath);
      this.svgPath = await _firebaseService.getDownloadUrl(level.solutionPath);
    }

    isFactTypeLevel = !level.isHighlightType; // Use the public property
    isFactLevelComplete = false; // Reset completion flag
    solutionOpacity = 0.0; // Reset opacity for new level
    _isFadingIn = true; // Reset animation direction
    _solutionAnimationTimer?.cancel(); // Cancel any previous animation

    if (level.isHighlightType) {
      highlightLetters = await _loadSvgLetters(svgPath: this.svgPath);
    } else {
      highlightLetters = []; // No SVG letters for 'fact' type levels
    }
    notifyListeners(); // Notify once after all properties are set
  }

  Future<List<SvgLetter>> _loadSvgLetters({required String svgPath}) async {
    if (svgPath.isEmpty) return [];

    String svgString;
    if (svgPath.startsWith('http')) {
      final response = await http.get(Uri.parse(svgPath));
      svgString = response.body;
    } else {
      // This is the potentially blocking call. The delay in LevelModel ensures
      // the UI is responsive before this runs.
      svgString = await rootBundle.loadString(svgPath);
    }
    return _parseSvg(svgString);
  }

  void setLevelComplete()
  {
    if (isFactTypeLevel) {
      // For 'fact' levels, just set the flag. The animation will be
      // triggered by the UI once the image is confirmed to be loaded.
      isFactLevelComplete = true;
      notifyListeners();
    } else {
      // For 'highlight' levels, show all the SVG letters.
      for (var element in highlightLetters) { element.show = true; }
      notifyListeners(); // Notify for highlight changes
    }
  }

  /// This method is called by the UI once the solution image is loaded and ready.
  void beginSolutionAnimation() {
    // Only start if it's a completed fact level and the timer isn't already running.
    if (isFactLevelComplete && _solutionAnimationTimer == null) {
      _startSolutionAnimationLoop();
    }
  }

  void _startSolutionAnimationLoop() {
    _solutionAnimationTimer?.cancel(); // Ensure only one timer is active

    // --- 1. DURATION CONTROL ---
    // Set the duration for one direction of the fade (e.g., fade-in).
    // The total loop time will be twice this duration.
    const oneWayDuration = Duration(milliseconds: 3000);

    // --- 2. STYLE CONTROL ---
    // Choose the animation curve you want for the fade effect.
    // Examples: Curves.easeInOut, Curves.easeIn, Curves.linear, Curves.bounceInOut
    const animationCurve = Curves.easeIn;

    const frameDuration = Duration(milliseconds: 16); // ~60 FPS
    final totalFrames = oneWayDuration.inMilliseconds / frameDuration.inMilliseconds;
    final step = 1.0 / totalFrames;
    double progress = 0.0;

    _solutionAnimationTimer = Timer.periodic(frameDuration, (timer) {
      progress += step;
      if (progress > 1.0) {
        progress = 0.0; // Reset progress
        _isFadingIn = !_isFadingIn; // Reverse direction
      }

      // Apply the curve to the linear progress
      final curvedProgress = animationCurve.transform(progress);

      if (_isFadingIn) {
        solutionOpacity = curvedProgress;
      } else {
        solutionOpacity = 1.0 - curvedProgress;
      }
      notifyListeners(); // Notify UI to rebuild with new opacity
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
      _log.info('No highlight letters available for this level.');
      return;
    }

    var allHintsGiven = highlightLetters.every((element) => element.hintGiven == true);
    if (allHintsGiven) for (var element in highlightLetters) { element.hintGiven = false; }

    List<int> candidateIndices = highlightLetters
        .asMap()
        .entries
        .where((entry) => entry.value.hintGiven == false &&
            entry.value.show == false && // Only highlight letters that are not already shown
            availableLetters.contains(entry.value.letter.toUpperCase()))
        .map((entry) => entry.key)
        .toList();

    if (candidateIndices.isEmpty) {
      _log.info('No candidate letters to highlight.');
      return;
    }

    var letterIndexToHighlight = candidateIndices.sample(1, Random()).first;
    highlightLetters[letterIndexToHighlight].show = true;
    highlightLetters[letterIndexToHighlight].hintGiven = true;
    notifyListeners();
  }

  void hideLetter(String letter) {
    int index = highlightLetters.indexWhere((item) => item.letter.toUpperCase() == letter.toUpperCase());
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
      final id = element.getAttribute('id');
      final path = element.getAttribute('d');
      if (id != null && path != null) {
        var svgLetter = SvgLetter(path: path, letter: id);
        if (id.length <= 3) letters.add(svgLetter);
      }
    }
    return letters;
  }

  void reset() {
    scale = 1.0;
    quarterTurn = 0;
    notifyListeners();
  }

 
}
