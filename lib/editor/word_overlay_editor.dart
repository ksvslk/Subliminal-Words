import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:xml/xml.dart';

class WordOverlayLetter {
  final String id;
  final String letter;
  final Offset normalizedCenter;
  final double fontSize;
  final double rotationDegrees;
  final double scaleX;
  final double scaleY;
  final double skewXDegrees;
  final double skewYDegrees;
  final double opacity;

  const WordOverlayLetter({
    required this.id,
    required this.letter,
    required this.normalizedCenter,
    required this.fontSize,
    required this.rotationDegrees,
    required this.scaleX,
    required this.scaleY,
    required this.skewXDegrees,
    required this.skewYDegrees,
    required this.opacity,
  });

  WordOverlayLetter copyWith({
    String? id,
    String? letter,
    Offset? normalizedCenter,
    double? fontSize,
    double? rotationDegrees,
    double? scaleX,
    double? scaleY,
    double? skewXDegrees,
    double? skewYDegrees,
    double? opacity,
  }) {
    return WordOverlayLetter(
      id: id ?? this.id,
      letter: letter ?? this.letter,
      normalizedCenter: normalizedCenter ?? this.normalizedCenter,
      fontSize: fontSize ?? this.fontSize,
      rotationDegrees: rotationDegrees ?? this.rotationDegrees,
      scaleX: scaleX ?? this.scaleX,
      scaleY: scaleY ?? this.scaleY,
      skewXDegrees: skewXDegrees ?? this.skewXDegrees,
      skewYDegrees: skewYDegrees ?? this.skewYDegrees,
      opacity: opacity ?? this.opacity,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'letter': letter,
      'x': normalizedCenter.dx,
      'y': normalizedCenter.dy,
      'fontSize': fontSize,
      'rotationDegrees': rotationDegrees,
      'scaleX': scaleX,
      'scaleY': scaleY,
      'skewXDegrees': skewXDegrees,
      'skewYDegrees': skewYDegrees,
      'opacity': opacity,
    };
  }

  factory WordOverlayLetter.fromJson(Map<String, dynamic> json) {
    return WordOverlayLetter(
      id: json['id'] as String? ?? '',
      letter: json['letter'] as String? ?? '',
      normalizedCenter: Offset(
        (json['x'] as num?)?.toDouble() ?? 0.5,
        (json['y'] as num?)?.toDouble() ?? 0.5,
      ),
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 148,
      rotationDegrees: (json['rotationDegrees'] as num?)?.toDouble() ?? 0,
      scaleX: (json['scaleX'] as num?)?.toDouble() ?? 1,
      scaleY: (json['scaleY'] as num?)?.toDouble() ?? 1,
      skewXDegrees: (json['skewXDegrees'] as num?)?.toDouble() ?? 0,
      skewYDegrees: (json['skewYDegrees'] as num?)?.toDouble() ?? 0,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1,
    );
  }
}

List<String> extractWordSolutionCharacters(String solution) {
  return solution.characters
      .where((character) => character.trim().isNotEmpty)
      .toList(growable: false);
}

List<WordOverlayLetter> buildWordOverlayLettersFromSolution(String solution) {
  final characters = extractWordSolutionCharacters(solution);
  if (characters.isEmpty) {
    return const <WordOverlayLetter>[];
  }

  const viewSize = 1024.0;
  const baseSpacing = 184.0;
  const rowSpacing = 214.0;
  final columns = math.max(1, math.min(4, characters.length));
  final rows = (characters.length / columns).ceil();
  final letters = <WordOverlayLetter>[];

  for (var index = 0; index < characters.length; index += 1) {
    final row = index ~/ columns;
    final column = index % columns;
    final rowCount = math.min(columns, characters.length - (row * columns));
    final x = (viewSize / 2) -
        ((rowCount - 1) * baseSpacing / 2) +
        column * baseSpacing;
    final y = (viewSize / 2) - ((rows - 1) * rowSpacing / 2) + row * rowSpacing;

    letters.add(
      WordOverlayLetter(
        id: 'letter_${index + 1}',
        letter: characters[index],
        normalizedCenter: Offset(x / viewSize, y / viewSize),
        fontSize: 152,
        rotationDegrees: 0,
        scaleX: 1,
        scaleY: 1,
        skewXDegrees: 0,
        skewYDegrees: 0,
        opacity: 1,
      ),
    );
  }

  return letters;
}

class WordOverlayController extends ChangeNotifier {
  WordOverlayController({
    Iterable<WordOverlayLetter> initialLetters = const <WordOverlayLetter>[],
  }) : _letters = List<WordOverlayLetter>.from(initialLetters);

  final List<WordOverlayLetter> _letters;
  String? _selectedLetterId;
  int _contentVersion = 0;

  UnmodifiableListView<WordOverlayLetter> get letters =>
      UnmodifiableListView<WordOverlayLetter>(_letters);

  String? get selectedLetterId => _selectedLetterId;

  WordOverlayLetter? get selectedLetter {
    final selectedId = _selectedLetterId;
    if (selectedId == null) {
      return null;
    }

    for (final letter in _letters) {
      if (letter.id == selectedId) {
        return letter;
      }
    }
    return null;
  }

  bool get hasLetters => _letters.isNotEmpty;

  int get contentVersion => _contentVersion;

  void selectLetter(String? letterId) {
    if (_selectedLetterId == letterId) {
      return;
    }

    _selectedLetterId = letterId;
    notifyListeners();
  }

  void replaceLetters(
    Iterable<WordOverlayLetter> newLetters, {
    String? selectedLetterId,
  }) {
    final nextLetters = List<WordOverlayLetter>.from(newLetters);
    final nextSelectedLetterId = selectedLetterId != null &&
            nextLetters.any((letter) => letter.id == selectedLetterId)
        ? selectedLetterId
        : null;

    if (_sameLetterLists(_letters, nextLetters) &&
        _selectedLetterId == nextSelectedLetterId) {
      return;
    }

    _letters
      ..clear()
      ..addAll(nextLetters);
    _selectedLetterId = nextSelectedLetterId;
    _contentVersion += 1;
    notifyListeners();
  }

  void rebuildFromSolution(String solution) {
    replaceLetters(buildWordOverlayLettersFromSolution(solution));
  }

  void syncToSolution(String solution) {
    final templates = buildWordOverlayLettersFromSolution(solution);
    final existingById = <String, WordOverlayLetter>{
      for (final letter in _letters) letter.id: letter,
    };
    final merged = <WordOverlayLetter>[
      for (final template in templates)
        (existingById[template.id] ?? template)
            .copyWith(letter: template.letter),
    ];

    final selectedLetterId = _selectedLetterId;
    replaceLetters(
      merged,
      selectedLetterId: selectedLetterId != null &&
              merged.any((letter) => letter.id == selectedLetterId)
          ? selectedLetterId
          : null,
    );
  }

  void moveLetterBy(String letterId, Offset deltaNormalized) {
    final index = _letters.indexWhere((letter) => letter.id == letterId);
    if (index == -1) {
      return;
    }

    final current = _letters[index];
    final nextCenter = Offset(
      (current.normalizedCenter.dx + deltaNormalized.dx).clamp(0.08, 0.92),
      (current.normalizedCenter.dy + deltaNormalized.dy).clamp(0.08, 0.92),
    );
    _letters[index] = current.copyWith(normalizedCenter: nextCenter);
    _contentVersion += 1;
    notifyListeners();
  }

  void updateLetterCenter(String letterId, Offset normalizedCenter) {
    final index = _letters.indexWhere((letter) => letter.id == letterId);
    if (index == -1) {
      return;
    }

    final current = _letters[index];
    final nextCenter = Offset(
      normalizedCenter.dx.clamp(0.08, 0.92),
      normalizedCenter.dy.clamp(0.08, 0.92),
    );
    if (nextCenter == current.normalizedCenter) {
      return;
    }

    _letters[index] = current.copyWith(normalizedCenter: nextCenter);
    _contentVersion += 1;
    notifyListeners();
  }

  void replaceLetter(WordOverlayLetter nextLetter) {
    final index = _letters.indexWhere((letter) => letter.id == nextLetter.id);
    if (index == -1) {
      return;
    }

    final current = _letters[index];
    if (current.id == nextLetter.id &&
        current.letter == nextLetter.letter &&
        current.normalizedCenter == nextLetter.normalizedCenter &&
        current.fontSize == nextLetter.fontSize &&
        current.rotationDegrees == nextLetter.rotationDegrees &&
        current.scaleX == nextLetter.scaleX &&
        current.scaleY == nextLetter.scaleY &&
        current.skewXDegrees == nextLetter.skewXDegrees &&
        current.skewYDegrees == nextLetter.skewYDegrees &&
        current.opacity == nextLetter.opacity) {
      return;
    }

    _letters[index] = nextLetter;
    _contentVersion += 1;
    notifyListeners();
  }

  void updateSelectedFontSize(double fontSize) {
    final selected = selectedLetter;
    if (selected == null) {
      return;
    }

    final clamped = fontSize.clamp(56.0, 260.0);
    if ((selected.fontSize - clamped).abs() < 0.1) {
      return;
    }

    _updateLetter(
      selected.id,
      selected.copyWith(fontSize: clamped),
    );
  }

  void updateSelectedRotation(double rotationDegrees) {
    final selected = selectedLetter;
    if (selected == null) {
      return;
    }

    final normalized = rotationDegrees.clamp(-180.0, 180.0);
    if ((selected.rotationDegrees - normalized).abs() < 0.1) {
      return;
    }

    _updateLetter(
      selected.id,
      selected.copyWith(rotationDegrees: normalized),
    );
  }

  void updateSelectedScaleX(double scaleX) {
    final selected = selectedLetter;
    if (selected == null) {
      return;
    }

    updateSelectedScales(scaleX, selected.scaleY);
  }

  void updateSelectedScaleY(double scaleY) {
    final selected = selectedLetter;
    if (selected == null) {
      return;
    }

    updateSelectedScales(selected.scaleX, scaleY);
  }

  void updateSelectedScales(double scaleX, double scaleY) {
    final selected = selectedLetter;
    if (selected == null) {
      return;
    }

    final clampedScaleX = scaleX.clamp(0.01, 1000.0);
    final clampedScaleY = scaleY.clamp(0.01, 1000.0);
    if ((selected.scaleX - clampedScaleX).abs() < 0.001 &&
        (selected.scaleY - clampedScaleY).abs() < 0.001) {
      return;
    }

    _updateLetter(
      selected.id,
      selected.copyWith(scaleX: clampedScaleX, scaleY: clampedScaleY),
    );
  }

  void updateSelectedSkewX(double skewXDegrees) {
    final selected = selectedLetter;
    if (selected == null) {
      return;
    }

    _updateLetter(
      selected.id,
      selected.copyWith(skewXDegrees: skewXDegrees.clamp(-40.0, 40.0)),
    );
  }

  void updateSelectedSkewY(double skewYDegrees) {
    final selected = selectedLetter;
    if (selected == null) {
      return;
    }

    _updateLetter(
      selected.id,
      selected.copyWith(skewYDegrees: skewYDegrees.clamp(-40.0, 40.0)),
    );
  }

  void updateSelectedOpacity(double opacity) {
    final selected = selectedLetter;
    if (selected == null) {
      return;
    }

    _updateLetter(
      selected.id,
      selected.copyWith(opacity: opacity.clamp(0.05, 1.0)),
    );
  }

  void nudgeSelectedFontSize(double delta) {
    final selected = selectedLetter;
    if (selected == null) {
      return;
    }
    updateSelectedFontSize(selected.fontSize + delta);
  }

  void nudgeSelectedRotation(double deltaDegrees) {
    final selected = selectedLetter;
    if (selected == null) {
      return;
    }
    updateSelectedRotation(selected.rotationDegrees + deltaDegrees);
  }

  void nudgeSelectedScaleX(double delta) {
    final selected = selectedLetter;
    if (selected == null) {
      return;
    }
    updateSelectedScaleX(selected.scaleX + delta);
  }

  void nudgeSelectedScaleY(double delta) {
    final selected = selectedLetter;
    if (selected == null) {
      return;
    }
    updateSelectedScaleY(selected.scaleY + delta);
  }

  void nudgeSelectedSkewX(double deltaDegrees) {
    final selected = selectedLetter;
    if (selected == null) {
      return;
    }
    updateSelectedSkewX(selected.skewXDegrees + deltaDegrees);
  }

  void nudgeSelectedOpacity(double delta) {
    final selected = selectedLetter;
    if (selected == null) {
      return;
    }
    updateSelectedOpacity(selected.opacity + delta);
  }

  void deleteSelected() {
    final selectedId = _selectedLetterId;
    if (selectedId == null) {
      return;
    }

    final nextLetters = _letters
        .where((letter) => letter.id != selectedId)
        .toList(growable: false);
    replaceLetters(nextLetters);
  }

  void clear() {
    if (_letters.isEmpty) {
      return;
    }
    _letters.clear();
    _selectedLetterId = null;
    _contentVersion += 1;
    notifyListeners();
  }

  void _updateLetter(String letterId, WordOverlayLetter nextLetter) {
    final index = _letters.indexWhere((letter) => letter.id == letterId);
    if (index == -1) {
      return;
    }

    _letters[index] = nextLetter;
    _contentVersion += 1;
    notifyListeners();
  }

  bool _sameLetterLists(
    List<WordOverlayLetter> current,
    List<WordOverlayLetter> next,
  ) {
    if (identical(current, next)) {
      return true;
    }
    if (current.length != next.length) {
      return false;
    }

    for (var index = 0; index < current.length; index += 1) {
      final a = current[index];
      final b = next[index];
      if (a.id != b.id ||
          a.letter != b.letter ||
          a.normalizedCenter != b.normalizedCenter ||
          a.fontSize != b.fontSize ||
          a.rotationDegrees != b.rotationDegrees ||
          a.scaleX != b.scaleX ||
          a.scaleY != b.scaleY ||
          a.skewXDegrees != b.skewXDegrees ||
          a.skewYDegrees != b.skewYDegrees ||
          a.opacity != b.opacity) {
        return false;
      }
    }

    return true;
  }
}

String generateWordOverlaySvg(List<WordOverlayLetter> letters) {
  final buffer = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8" standalone="no"?>')
    ..writeln(
      '<svg width="1024" height="1024" viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg">',
    );

  for (final letter in letters) {
    final x = letter.normalizedCenter.dx * 1024;
    final y = letter.normalizedCenter.dy * 1024;
    final content = _escapeXml(letter.letter);
    final ariaLabel = _escapeXml(letter.letter);
    final id = _escapeXml(letter.id);

    buffer.writeln(
      '<text id="$id" aria-label="$ariaLabel" '
      'x="0" y="0" '
      'font-size="${letter.fontSize.toStringAsFixed(2)}" '
      'font-family="Roboto, Arial, sans-serif" '
      'text-anchor="middle" dominant-baseline="middle" fill="#000000" '
      'fill-opacity="${letter.opacity.toStringAsFixed(3)}" '
      'transform="translate(${x.toStringAsFixed(2)} ${y.toStringAsFixed(2)}) rotate(${letter.rotationDegrees.toStringAsFixed(2)}) skewX(${letter.skewXDegrees.toStringAsFixed(2)}) skewY(${letter.skewYDegrees.toStringAsFixed(2)}) scale(${letter.scaleX.toStringAsFixed(3)} ${letter.scaleY.toStringAsFixed(3)})" '
      'data-x="${x.toStringAsFixed(2)}" data-y="${y.toStringAsFixed(2)}" '
      'data-font-size="${letter.fontSize.toStringAsFixed(2)}" '
      'data-rotation="${letter.rotationDegrees.toStringAsFixed(2)}" '
      'data-scale-x="${letter.scaleX.toStringAsFixed(3)}" '
      'data-scale-y="${letter.scaleY.toStringAsFixed(3)}" '
      'data-skew-x="${letter.skewXDegrees.toStringAsFixed(2)}" '
      'data-skew-y="${letter.skewYDegrees.toStringAsFixed(2)}" '
      'data-opacity="${letter.opacity.toStringAsFixed(3)}">$content</text>',
    );
  }

  buffer.writeln('</svg>');
  return buffer.toString();
}

List<WordOverlayLetter> parseWordOverlayLetters(String svgString) {
  if (svgString.trim().isEmpty) {
    return const <WordOverlayLetter>[];
  }

  final document = XmlDocument.parse(svgString);
  final elements = document.findAllElements('text');
  final letters = <WordOverlayLetter>[];

  for (final element in elements) {
    final textContent = element.innerText.trim();
    final letter = (element.getAttribute('aria-label') ?? textContent).trim();
    if (letter.isEmpty) {
      continue;
    }

    final x = double.tryParse(
          element.getAttribute('x') ?? element.getAttribute('data-x') ?? '',
        ) ??
        512;
    final y = double.tryParse(
          element.getAttribute('y') ?? element.getAttribute('data-y') ?? '',
        ) ??
        512;
    final fontSize = double.tryParse(
          element.getAttribute('font-size') ??
              element.getAttribute('data-font-size') ??
              '',
        ) ??
        152;
    final rotation = double.tryParse(
          element.getAttribute('data-rotation') ?? '',
        ) ??
        _rotationFromTransform(element.getAttribute('transform'));

    letters.add(
      WordOverlayLetter(
        id: element.getAttribute('id') ?? 'letter_${letters.length + 1}',
        letter: letter,
        normalizedCenter:
            Offset((x / 1024).clamp(0.0, 1.0), (y / 1024).clamp(0.0, 1.0)),
        fontSize: fontSize,
        rotationDegrees: rotation,
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
      ),
    );
  }

  return letters;
}

double _rotationFromTransform(String? transform) {
  final normalized = transform ?? '';
  final match = RegExp(r'rotate\(([-\d.]+)').firstMatch(normalized);
  if (match == null) {
    return 0;
  }

  return double.tryParse(match.group(1) ?? '') ?? 0;
}

String _escapeXml(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}

class WordOverlayStage extends StatefulWidget {
  final WordOverlayController controller;
  final bool isLocked;
  final ValueChanged<bool> onInteractionChanged;
  final Color borderColor;
  final Color backgroundColor;
  final Color foregroundColor;

  const WordOverlayStage({
    super.key,
    required this.controller,
    required this.isLocked,
    required this.onInteractionChanged,
    required this.borderColor,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  @override
  State<WordOverlayStage> createState() => _WordOverlayStageState();
}

class _WordOverlayStageState extends State<WordOverlayStage> {
  final GlobalKey _stageKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: widget.backgroundColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: widget.borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(1),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(23),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(constraints.maxWidth, constraints.maxHeight);

              return Listener(
                onPointerDown: (_) {
                  if (!widget.isLocked && widget.controller.hasLetters) {
                    widget.onInteractionChanged(true);
                  }
                },
                onPointerUp: (_) => widget.onInteractionChanged(false),
                onPointerCancel: (_) => widget.onInteractionChanged(false),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => widget.controller.selectLetter(null),
                  child: RepaintBoundary(
                    child: Stack(
                      key: _stageKey,
                      fit: StackFit.expand,
                      children: <Widget>[
                        AnimatedBuilder(
                          animation: widget.controller,
                          builder: (context, _) {
                            final letters = widget.controller.letters;
                            final selectedId = widget.controller.selectedLetterId;
                            final orderedLetters = <WordOverlayLetter>[
                              ...letters.where((letter) => letter.id != selectedId),
                              ...letters.where((letter) => letter.id == selectedId),
                            ];

                            return Stack(
                              fit: StackFit.expand,
                              children: <Widget>[
                                if (letters.isEmpty)
                                  IgnorePointer(
                                    child: _WordStagePlaceholder(
                                      icon: Icons.text_fields_rounded,
                                      title: 'Solution stage',
                                      subtitle:
                                          'Type the solution below, then position letters here.',
                                      foregroundColor: widget.foregroundColor,
                                    ),
                                  ),
                                for (final letter in orderedLetters)
                                  _WordLetterHandle(
                                    key: ValueKey<String>(letter.id),
                                    stageKey: _stageKey,
                                    controller: widget.controller,
                                    letter: letter,
                                    size: size,
                                    selected: selectedId == letter.id,
                                    isLocked: widget.isLocked,
                                    foregroundColor: widget.foregroundColor,
                                    onInteractionChanged:
                                        widget.onInteractionChanged,
                                    onTap: () =>
                                        widget.controller.selectLetter(letter.id),
                                  ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _WordLetterHandle extends StatefulWidget {
  final GlobalKey stageKey;
  final WordOverlayController controller;
  final WordOverlayLetter letter;
  final Size size;
  final bool selected;
  final bool isLocked;
  final Color foregroundColor;
  final ValueChanged<bool> onInteractionChanged;
  final VoidCallback onTap;

  const _WordLetterHandle({
    super.key,
    required this.stageKey,
    required this.controller,
    required this.letter,
    required this.size,
    required this.selected,
    required this.isLocked,
    required this.foregroundColor,
    required this.onInteractionChanged,
    required this.onTap,
  });

  @override
  State<_WordLetterHandle> createState() => _WordLetterHandleState();
}

class _WordLetterHandleState extends State<_WordLetterHandle> {
  static const double _moveStartThreshold = 4.0;
  static const double _selectedInteractionPadding = 12.0;
  static const double _unselectedInteractionPadding = 4.0;

  double? _rotationStartAngle;
  double? _rotationStartDegrees;
  _ResizeHandle? _resizeHandle;
  double? _resizeStartScaleX;
  double? _resizeStartScaleY;
  double? _resizeStartHorizontalExtent;
  double? _resizeStartVerticalExtent;
  int? _movePointerId;
  Offset? _moveDownGlobal;
  bool _moveWasSelectedOnDown = false;
  bool _moveHasStarted = false;
  Offset? _moveGrabOffset;
  WordOverlayLetter? _draftLetter;
  _TransformMode _transformMode = _TransformMode.resize;
  bool _consumeNextTapAfterSelection = false;

  @override
  void didUpdateWidget(covariant _WordLetterHandle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.selected || oldWidget.selected != widget.selected) {
      _transformMode = _TransformMode.resize;
    }
    if (_draftLetter != null && !_isInteracting) {
      _draftLetter = null;
    }
  }

  bool get _isInteracting =>
      _rotationStartAngle != null ||
      _resizeHandle != null ||
      _movePointerId != null;

  WordOverlayLetter get _currentLetter => _draftLetter ?? widget.letter;

  RenderBox? _stageRenderBox() {
    final renderObject = widget.stageKey.currentContext?.findRenderObject();
    return renderObject is RenderBox ? renderObject : null;
  }

  Offset _stageLocalFromGlobal(Offset globalPosition) {
    final renderBox = _stageRenderBox();
    if (renderBox == null) {
      return Offset.zero;
    }
    return renderBox.globalToLocal(globalPosition);
  }

  Offset _letterCenterOnStage() {
    final currentLetter = _currentLetter;
    return Offset(
      currentLetter.normalizedCenter.dx * widget.size.width,
      currentLetter.normalizedCenter.dy * widget.size.height,
    );
  }

  Offset _vectorFromCenter(Offset globalPosition) {
    final local = _stageLocalFromGlobal(globalPosition);
    return local - _letterCenterOnStage();
  }

  _LetterSelectionMetrics _measureSelection(WordOverlayLetter letter) {
    final scale = widget.size.width / 1024;
    final visualFontSize = letter.fontSize * scale;
    const outlineWidth = 3.5;
    final textPainter = TextPainter(
      text: TextSpan(
        text: letter.letter,
        style: TextStyle(
          fontSize: visualFontSize,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();
    final baseBounds = _measureGlyphBounds(
      textPainter: textPainter,
      outlineWidth: outlineWidth,
    );
    final frameBounds = _expandSelectionFrameBounds(baseBounds);
    final corners = <Offset>[
      frameBounds.topLeft,
      frameBounds.topRight,
      frameBounds.bottomRight,
      frameBounds.bottomLeft,
    ].map((corner) => _transformLocalPoint(corner, letter)).toList();
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;
    for (final corner in corners) {
      minX = math.min(minX, corner.dx);
      minY = math.min(minY, corner.dy);
      maxX = math.max(maxX, corner.dx);
      maxY = math.max(maxY, corner.dy);
    }
    return _LetterSelectionMetrics(
      visualFontSize: visualFontSize,
      baseBounds: baseBounds,
      frameBounds: frameBounds,
      transformedBounds: Rect.fromLTRB(minX, minY, maxX, maxY),
    );
  }

  Rect _measureGlyphBounds({
    required TextPainter textPainter,
    required double outlineWidth,
  }) {
    final selection = TextSelection(
      baseOffset: 0,
      extentOffset: _currentLetter.letter.length,
    );
    final boxes = textPainter.getBoxesForSelection(selection);
    if (boxes.isEmpty) {
      final fallbackBounds = Rect.fromCenter(
        center: Offset.zero,
        width: textPainter.width + (outlineWidth * 2),
        height: textPainter.height + (outlineWidth * 2),
      );
      return _tightenGlyphBounds(fallbackBounds);
    }

    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;
    for (final box in boxes) {
      minX = math.min(minX, box.left);
      minY = math.min(minY, box.top);
      maxX = math.max(maxX, box.right);
      maxY = math.max(maxY, box.bottom);
    }

    final rawBounds = Rect.fromLTRB(
      minX - (textPainter.width / 2) - outlineWidth,
      minY - (textPainter.height / 2) - outlineWidth,
      maxX - (textPainter.width / 2) + outlineWidth,
      maxY - (textPainter.height / 2) + outlineWidth,
    );
    return _tightenGlyphBounds(rawBounds);
  }

  Rect _tightenGlyphBounds(Rect rawBounds) {
    final grapheme = _currentLetter.letter.trim();
    if (grapheme.isEmpty) {
      return rawBounds;
    }

    final uppercaseOnly = grapheme == grapheme.toUpperCase() &&
        grapheme != grapheme.toLowerCase();
    final hasDescender = RegExp(r'[gjpqyQJ]').hasMatch(grapheme);
    final horizontalInset = rawBounds.width * 0.11;
    final topInset = rawBounds.height * (uppercaseOnly ? 0.2 : 0.24);
    final bottomInset = rawBounds.height * (hasDescender ? 0.08 : 0.2);

    final tightened = Rect.fromLTRB(
      rawBounds.left + horizontalInset,
      rawBounds.top + topInset,
      rawBounds.right - horizontalInset,
      rawBounds.bottom - bottomInset,
    );

    final minWidth = math.max(10.0, rawBounds.width * 0.2);
    final minHeight = math.max(14.0, rawBounds.height * 0.3);
    final nextWidth = math.max(minWidth, tightened.width);
    final nextHeight = math.max(minHeight, tightened.height);

    return Rect.fromCenter(
      center: tightened.center,
      width: nextWidth,
      height: nextHeight,
    );
  }

  Rect _expandSelectionFrameBounds(Rect baseBounds) {
    final outwardPadding =
        math.max(4.0, math.min(8.0, baseBounds.shortestSide * 0.07));
    return baseBounds.inflate(outwardPadding);
  }

  Offset _transformLocalPoint(Offset point, WordOverlayLetter letter) {
    final scaled = Offset(point.dx * letter.scaleX, point.dy * letter.scaleY);
    final skewX = math.tan(letter.skewXDegrees * math.pi / 180);
    final skewY = math.tan(letter.skewYDegrees * math.pi / 180);
    final skewed = Offset(
      scaled.dx + (skewX * scaled.dy),
      (skewY * scaled.dx) + scaled.dy,
    );
    final rotation = letter.rotationDegrees * math.pi / 180;
    final cosTheta = math.cos(rotation);
    final sinTheta = math.sin(rotation);
    return Offset(
      (skewed.dx * cosTheta) - (skewed.dy * sinTheta),
      (skewed.dx * sinTheta) + (skewed.dy * cosTheta),
    );
  }

  void _startRotation(Offset globalPosition) {
    _draftLetter = _currentLetter;
    _rotationStartAngle = _vectorFromCenter(globalPosition).direction;
    _rotationStartDegrees = _currentLetter.rotationDegrees;
    widget.onTap();
    widget.onInteractionChanged(true);
  }

  void _updateRotation(Offset globalPosition) {
    final startAngle = _rotationStartAngle;
    final startDegrees = _rotationStartDegrees;
    if (startAngle == null || startDegrees == null) {
      return;
    }

    final currentAngle = _vectorFromCenter(globalPosition).direction;
    final rawDelta = currentAngle - startAngle;
    final normalizedDelta =
        math.atan2(math.sin(rawDelta), math.cos(rawDelta)) * 180 / math.pi;
    setState(() {
      _draftLetter = _currentLetter.copyWith(
        rotationDegrees: (startDegrees + normalizedDelta).clamp(-180.0, 180.0),
      );
    });
  }

  void _startResize(
    Offset globalPosition,
    _ResizeHandle handle,
    _LetterSelectionMetrics metrics,
  ) {
    final currentLetter = _currentLetter;
    _draftLetter = currentLetter;
    _resizeHandle = handle;
    _resizeStartScaleX = currentLetter.scaleX;
    _resizeStartScaleY = currentLetter.scaleY;
    _resizeStartHorizontalExtent = switch (handle.xSign) {
      -1 => metrics.baseBounds.left.abs() * currentLetter.scaleX,
      1 => metrics.baseBounds.right.abs() * currentLetter.scaleX,
      _ => null,
    };
    _resizeStartVerticalExtent = switch (handle.ySign) {
      -1 => metrics.baseBounds.top.abs() * currentLetter.scaleY,
      1 => metrics.baseBounds.bottom.abs() * currentLetter.scaleY,
      _ => null,
    };
    widget.onTap();
    widget.onInteractionChanged(true);
  }

  void _updateResize(Offset globalPosition) {
    final handle = _resizeHandle;
    final startScaleX = _resizeStartScaleX;
    final startScaleY = _resizeStartScaleY;
    if (handle == null ||
        startScaleX == null ||
        startScaleY == null) {
      return;
    }

    final vector = _inverseRotate(_vectorFromCenter(globalPosition));
    final currentLetter = _currentLetter;
    var nextScaleX = startScaleX;
    var nextScaleY = startScaleY;
    double? ratioX;
    double? ratioY;

    if (handle.xSign != 0) {
      final startExtentX = _resizeStartHorizontalExtent;
      if (startExtentX != null && startExtentX > 0) {
        final nextExtentX = math.max(12.0, handle.xSign * vector.dx);
        ratioX = nextExtentX / startExtentX;
        nextScaleX = startScaleX * ratioX;
      }
    }

    if (handle.ySign != 0) {
      final startExtentY = _resizeStartVerticalExtent;
      if (startExtentY != null && startExtentY > 0) {
        final nextExtentY = math.max(12.0, handle.ySign * vector.dy);
        ratioY = nextExtentY / startExtentY;
        nextScaleY = startScaleY * ratioY;
      }
    }

    if (handle.xSign == 0 && handle.ySign != 0) {
      nextScaleX = startScaleX;
    }
    if (handle.ySign == 0 && handle.xSign != 0) {
      nextScaleY = startScaleY;
    }

    if (handle.xSign != 0 && handle.ySign != 0) {
      final ratios = <double>[
        if (ratioX != null) ratioX,
        if (ratioY != null) ratioY,
      ];
      if (ratios.isNotEmpty) {
        final uniformRatio =
            ratios.reduce((sum, value) => sum + value) / ratios.length;
        nextScaleX = startScaleX * uniformRatio;
        nextScaleY = startScaleY * uniformRatio;
      }
    }

    setState(() {
      _draftLetter = currentLetter.copyWith(
        scaleX: nextScaleX.clamp(0.01, 1000.0),
        scaleY: nextScaleY.clamp(0.01, 1000.0),
      );
    });
  }

  Offset _inverseRotate(Offset point) {
    final rotation = -(_currentLetter.rotationDegrees * math.pi / 180);
    final cosTheta = math.cos(rotation);
    final sinTheta = math.sin(rotation);
    return Offset(
      (point.dx * cosTheta) - (point.dy * sinTheta),
      (point.dx * sinTheta) + (point.dy * cosTheta),
    );
  }

  void _startMove(
    Offset globalPosition, {
    required bool shouldSelect,
  }) {
    _draftLetter = _currentLetter;
    _moveGrabOffset = _stageLocalFromGlobal(globalPosition) - _letterCenterOnStage();
    if (shouldSelect) {
      widget.onTap();
      _transformMode = _TransformMode.resize;
    }
    widget.onInteractionChanged(true);
  }

  void _updateMove(Offset globalPosition) {
    final grabOffset = _moveGrabOffset;
    if (grabOffset == null) {
      return;
    }

    final stageLocal = _stageLocalFromGlobal(globalPosition);
    final nextCenter = stageLocal - grabOffset;
    setState(() {
      _draftLetter = _currentLetter.copyWith(
        normalizedCenter: Offset(
          (nextCenter.dx / widget.size.width).clamp(0.08, 0.92),
          (nextCenter.dy / widget.size.height).clamp(0.08, 0.92),
        ),
      );
    });
  }

  void _toggleTransformMode() {
    if (!widget.selected || widget.isLocked) {
      return;
    }
    setState(() {
      _transformMode = _transformMode == _TransformMode.resize
          ? _TransformMode.rotate
          : _TransformMode.resize;
    });
  }

  void _handleLetterTap() {
    if (widget.isLocked) {
      return;
    }
    if (_consumeNextTapAfterSelection) {
      _consumeNextTapAfterSelection = false;
      return;
    }
    if (widget.selected) {
      if (_transformMode != _TransformMode.resize) {
        setState(() {
          _transformMode = _TransformMode.resize;
        });
      }
      return;
    }
    widget.onTap();
    setState(() {
      _transformMode = _TransformMode.resize;
    });
  }

  void _onMovePointerDown(PointerDownEvent event) {
    if (widget.isLocked) {
      return;
    }
    if (!widget.selected) {
      widget.onTap();
      _transformMode = _TransformMode.resize;
      _consumeNextTapAfterSelection = true;
    }
    _movePointerId = event.pointer;
    _moveDownGlobal = event.position;
    _moveWasSelectedOnDown = true;
    _moveHasStarted = false;
  }

  void _onMovePointerMove(PointerMoveEvent event) {
    if (_movePointerId != event.pointer) {
      return;
    }

    if (!_moveHasStarted) {
      final downGlobal = _moveDownGlobal;
      if (downGlobal == null) {
        return;
      }
      final moveThreshold = _moveWasSelectedOnDown ? 0.5 : _moveStartThreshold;
      if ((event.position - downGlobal).distance <= moveThreshold) {
        return;
      }
      _moveHasStarted = true;
      _startMove(
        downGlobal,
        shouldSelect: !_moveWasSelectedOnDown,
      );
    }

    _updateMove(event.position);
  }

  void _onMovePointerUp(PointerUpEvent event) {
    if (_movePointerId != event.pointer) {
      return;
    }

    if (_moveHasStarted) {
      _finishInteraction();
      return;
    }

    _movePointerId = null;
    _moveDownGlobal = null;
    _moveWasSelectedOnDown = false;
    _moveHasStarted = false;
  }

  void _onMovePointerCancel(PointerCancelEvent event) {
    if (_movePointerId != event.pointer) {
      return;
    }

    if (_moveHasStarted) {
      _finishInteraction();
      return;
    }

    _movePointerId = null;
    _moveDownGlobal = null;
    _moveWasSelectedOnDown = false;
    _moveHasStarted = false;
    _consumeNextTapAfterSelection = false;
  }

  void _finishInteraction() {
    final draftLetter = _draftLetter;
    _rotationStartAngle = null;
    _rotationStartDegrees = null;
    _resizeHandle = null;
    _resizeStartScaleX = null;
    _resizeStartScaleY = null;
    _resizeStartHorizontalExtent = null;
    _resizeStartVerticalExtent = null;
    _movePointerId = null;
    _moveDownGlobal = null;
    _moveWasSelectedOnDown = false;
    _moveHasStarted = false;
    _moveGrabOffset = null;
    _consumeNextTapAfterSelection = false;
    if (draftLetter != null) {
      widget.controller.replaceLetter(draftLetter);
      _draftLetter = null;
    }
    widget.onInteractionChanged(false);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final letter = _currentLetter;
    final selected = widget.selected;
    final isLocked = widget.isLocked;
    final metrics = _measureSelection(letter);
    final visualFontSize = metrics.visualFontSize;
    const outlineWidth = 3.5;
    final fillColor = Colors.black.withValues(alpha: letter.opacity);
    final outlineColor = colorScheme.surface;
    final bounds = metrics.transformedBounds;
    final baseBounds = metrics.baseBounds;
    final frameBounds = metrics.frameBounds;
    const handleHitSize = 30.0;
    const handleVisualSize = 12.0;
    final centerX = math.max(bounds.left.abs(), bounds.right.abs()) +
        (handleHitSize / 2);
    final centerY = math.max(bounds.top.abs(), bounds.bottom.abs()) +
        (handleHitSize / 2);
    final totalWidth = centerX * 2;
    final totalHeight = centerY * 2;

    final labelVisual = Stack(
      alignment: Alignment.center,
      children: <Widget>[
        Text(
          letter.letter,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: visualFontSize,
            fontWeight: FontWeight.w900,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = outlineWidth
              ..color = outlineColor.withValues(
                alpha: math.min(1.0, 0.6 + (letter.opacity * 0.4)),
              ),
          ),
        ),
        Text(
          letter.letter,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: visualFontSize,
            fontWeight: FontWeight.w900,
            color: fillColor,
          ),
        ),
      ],
    );

    final stageCenter = Offset(
      letter.normalizedCenter.dx * widget.size.width,
      letter.normalizedCenter.dy * widget.size.height,
    );

    return Positioned(
      left: stageCenter.dx - (totalWidth / 2),
      top: stageCenter.dy - (totalHeight / 2),
      width: totalWidth,
      height: totalHeight,
      child: RepaintBoundary(
        child: SizedBox(
          width: totalWidth,
          height: totalHeight,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: <Widget>[
              Builder(
                builder: (context) {
                  Widget buildTransformed(Widget child) {
                    final skewScaleTransform = Matrix4.identity()
                      ..setEntry(
                          0, 1, math.tan(letter.skewXDegrees * math.pi / 180))
                      ..setEntry(
                          1, 0, math.tan(letter.skewYDegrees * math.pi / 180))
                      ..scaleByDouble(letter.scaleX, letter.scaleY, 1, 1);

                    return Transform.rotate(
                      angle: letter.rotationDegrees * math.pi / 180,
                      alignment: Alignment.center,
                      child: Transform(
                        alignment: Alignment.center,
                        transform: skewScaleTransform,
                        child: child,
                      ),
                    );
                  }

                  final skewScaleTransform = Matrix4.identity()
                    ..setEntry(
                        0, 1, math.tan(letter.skewXDegrees * math.pi / 180))
                    ..setEntry(
                        1, 0, math.tan(letter.skewYDegrees * math.pi / 180))
                    ..scaleByDouble(letter.scaleX, letter.scaleY, 1, 1);

                  final transformedVisual =
                      buildTransformed(IgnorePointer(child: labelVisual));

                  if (isLocked) {
                    return transformedVisual;
                  }

                  final interactionPadding = selected
                      ? _selectedInteractionPadding
                      : _unselectedInteractionPadding;
                  final interactionBox = SizedBox(
                    width: baseBounds.width + (interactionPadding * 2),
                    height: baseBounds.height + (interactionPadding * 2),
                    child: const ColoredBox(color: Colors.transparent),
                  );

                  return Transform.rotate(
                    angle: letter.rotationDegrees * math.pi / 180,
                    alignment: Alignment.center,
                    child: Transform(
                      alignment: Alignment.center,
                      transform: skewScaleTransform,
                      child: Listener(
                        behavior: HitTestBehavior.translucent,
                        onPointerDown: _onMovePointerDown,
                        onPointerMove: _onMovePointerMove,
                        onPointerUp: _onMovePointerUp,
                        onPointerCancel: _onMovePointerCancel,
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: _handleLetterTap,
                          child: Stack(
                            alignment: Alignment.center,
                            clipBehavior: Clip.none,
                            children: <Widget>[
                              Transform.translate(
                                offset: baseBounds.center,
                                child: interactionBox,
                              ),
                              IgnorePointer(child: labelVisual),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              if (selected)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _SelectionFramePainter(
                        points: _selectionCornerPoints(
                          baseBounds: frameBounds,
                          center: Offset(centerX, centerY),
                          letter: letter,
                        ),
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              if (selected && !isLocked)
                for (final handle in _visibleHandlesForMode(_transformMode))
                  Positioned(
                    left: centerX +
                        _handleLocalPoint(frameBounds, handle, letter).dx -
                        (handleHitSize / 2),
                    top: centerY +
                        _handleLocalPoint(frameBounds, handle, letter).dy -
                        (handleHitSize / 2),
                    child: _ResizeHandleButton(
                      size: handleHitSize,
                      visualSize: handleVisualSize,
                      color: colorScheme.primary,
                      icon: _transformMode == _TransformMode.rotate
                          ? Icons.rotate_right_rounded
                          : null,
                      onTap: _transformMode == _TransformMode.resize &&
                              handle.xSign != 0 &&
                              handle.ySign != 0
                          ? _toggleTransformMode
                          : null,
                      onPanStart: (details) => _transformMode == _TransformMode.rotate
                          ? _startRotation(details.globalPosition)
                          : _startResize(
                              details.globalPosition,
                              handle,
                              metrics,
                            ),
                      onPanUpdate: (details) => _transformMode == _TransformMode.rotate
                          ? _updateRotation(details.globalPosition)
                          : _updateResize(details.globalPosition),
                      onPanEnd: (_) => _finishInteraction(),
                      onPanCancel: _finishInteraction,
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  Offset _handleLocalPoint(
    Rect baseBounds,
    _ResizeHandle handle,
    WordOverlayLetter letter,
  ) {
    final basePoint = Offset(
      switch (handle.xSign) {
        -1 => baseBounds.left,
        1 => baseBounds.right,
        _ => baseBounds.center.dx,
      },
      switch (handle.ySign) {
        -1 => baseBounds.top,
        1 => baseBounds.bottom,
        _ => baseBounds.center.dy,
      },
    );
    return _transformLocalPoint(basePoint, letter);
  }

  List<Offset> _selectionCornerPoints({
    required Rect baseBounds,
    required Offset center,
    required WordOverlayLetter letter,
  }) {
    return <Offset>[
      baseBounds.topLeft,
      baseBounds.topRight,
      baseBounds.bottomRight,
      baseBounds.bottomLeft,
    ].map((point) => center + _transformLocalPoint(point, letter)).toList();
  }
}

enum _ResizeHandle {
  topLeft(-1, -1, Alignment.topLeft),
  topCenter(0, -1, Alignment.topCenter),
  topRight(1, -1, Alignment.topRight),
  centerLeft(-1, 0, Alignment.centerLeft),
  centerRight(1, 0, Alignment.centerRight),
  bottomLeft(-1, 1, Alignment.bottomLeft),
  bottomCenter(0, 1, Alignment.bottomCenter),
  bottomRight(1, 1, Alignment.bottomRight);

  const _ResizeHandle(this.xSign, this.ySign, this.alignment);

  final double xSign;
  final double ySign;
  final Alignment alignment;
}

enum _TransformMode {
  resize,
  rotate,
}

Iterable<_ResizeHandle> _visibleHandlesForMode(_TransformMode mode) {
  switch (mode) {
    case _TransformMode.resize:
      return _ResizeHandle.values;
    case _TransformMode.rotate:
      return const <_ResizeHandle>[
        _ResizeHandle.topLeft,
        _ResizeHandle.topRight,
        _ResizeHandle.bottomLeft,
        _ResizeHandle.bottomRight,
      ];
  }
}

class _LetterSelectionMetrics {
  const _LetterSelectionMetrics({
    required this.visualFontSize,
    required this.baseBounds,
    required this.frameBounds,
    required this.transformedBounds,
  });

  final double visualFontSize;
  final Rect baseBounds;
  final Rect frameBounds;
  final Rect transformedBounds;
}

class _SelectionFramePainter extends CustomPainter {
  final List<Offset> points;
  final Color color;

  const _SelectionFramePainter({
    required this.points,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length != 4) {
      return;
    }

    final path = Path()
      ..moveTo(points[0].dx, points[0].dy)
      ..lineTo(points[1].dx, points[1].dy)
      ..lineTo(points[2].dx, points[2].dy)
      ..lineTo(points[3].dx, points[3].dy)
      ..close();

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SelectionFramePainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.points != points;
  }
}

class _ResizeHandleButton extends StatelessWidget {
  final double size;
  final double visualSize;
  final Color color;
  final IconData? icon;
  final VoidCallback? onTap;
  final GestureDragStartCallback onPanStart;
  final GestureDragUpdateCallback onPanUpdate;
  final GestureDragEndCallback onPanEnd;
  final VoidCallback onPanCancel;

  const _ResizeHandleButton({
    required this.size,
    required this.visualSize,
    required this.color,
    this.icon,
    this.onTap,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
    required this.onPanCancel,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      dragStartBehavior: DragStartBehavior.down,
      onTap: onTap,
      onPanStart: onPanStart,
      onPanUpdate: onPanUpdate,
      onPanEnd: onPanEnd,
      onPanCancel: onPanCancel,
      child: SizedBox.square(
        dimension: size,
        child: Center(
          child: icon != null
              ? Icon(
                  icon,
                  size: 18,
                  color: color,
                )
              : DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: color, width: 1.2),
                  ),
                  child: SizedBox.square(dimension: visualSize),
                ),
        ),
      ),
    );
  }
}

class _WordStagePlaceholder extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color foregroundColor;

  const _WordStagePlaceholder({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 40, color: foregroundColor),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: textTheme.titleSmall?.copyWith(
                color: foregroundColor,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: foregroundColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<Uint8List> exportWordOverlayAsPng({
  required List<WordOverlayLetter> letters,
  required Color backgroundColor,
  int dimension = 1024,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final size = Size.square(dimension.toDouble());
  final backgroundPaint = Paint()..color = backgroundColor;
  canvas.drawRect(Offset.zero & size, backgroundPaint);

  for (final letter in letters) {
    _paintWordLetterToCanvas(
      canvas: canvas,
      size: size,
      letter: letter,
      color: Colors.black,
    );
  }

  final image = await recorder.endRecording().toImage(dimension, dimension);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  if (bytes == null) {
    throw StateError('Failed to export word overlay.');
  }

  return bytes.buffer.asUint8List();
}

void _paintWordLetterToCanvas({
  required Canvas canvas,
  required Size size,
  required WordOverlayLetter letter,
  required Color color,
}) {
  final center = Offset(
    letter.normalizedCenter.dx * size.width,
    letter.normalizedCenter.dy * size.height,
  );

  final textPainter = TextPainter(
    text: TextSpan(
      text: letter.letter,
      style: TextStyle(
        fontSize: letter.fontSize * (size.width / 1024),
        fontWeight: FontWeight.w900,
        color: color.withValues(alpha: letter.opacity),
      ),
    ),
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
  )..layout();

  canvas.save();
  canvas.translate(center.dx, center.dy);
  canvas.rotate(letter.rotationDegrees * math.pi / 180);
  final transform = Matrix4.identity()
    ..setEntry(0, 1, math.tan(letter.skewXDegrees * math.pi / 180))
    ..setEntry(1, 0, math.tan(letter.skewYDegrees * math.pi / 180));
  transform.scaleByDouble(letter.scaleX, letter.scaleY, 1, 1);
  canvas.transform(transform.storage);
  textPainter.paint(
    canvas,
    Offset(-textPainter.width / 2, -textPainter.height / 2),
  );
  canvas.restore();
}
