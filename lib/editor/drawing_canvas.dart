import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

enum DrawingBrushType {
  none,
  pencil,
  marker,
  charcoal,
  eraser,
}

extension DrawingBrushTypeX on DrawingBrushType {
  String get label {
    switch (this) {
      case DrawingBrushType.none:
        return 'No Tool';
      case DrawingBrushType.pencil:
        return 'Pencil';
      case DrawingBrushType.marker:
        return 'Marker';
      case DrawingBrushType.charcoal:
        return 'Charcoal';
      case DrawingBrushType.eraser:
        return 'Eraser';
    }
  }

  double get defaultOpacity {
    switch (this) {
      case DrawingBrushType.none:
        return 1.0;
      case DrawingBrushType.pencil:
        return 0.9;
      case DrawingBrushType.marker:
        return 0.7;
      case DrawingBrushType.charcoal:
        return 0.45;
      case DrawingBrushType.eraser:
        return 1.0;
    }
  }

  double get defaultWidth {
    switch (this) {
      case DrawingBrushType.none:
        return 0.012;
      case DrawingBrushType.pencil:
        return 0.012;
      case DrawingBrushType.marker:
        return 0.024;
      case DrawingBrushType.charcoal:
        return 0.034;
      case DrawingBrushType.eraser:
        return 0.04;
    }
  }

  Color get color {
    switch (this) {
      case DrawingBrushType.none:
        return const Color(0xFF111111);
      case DrawingBrushType.pencil:
        return const Color(0xFF111111);
      case DrawingBrushType.marker:
        return const Color(0xFF111111);
      case DrawingBrushType.charcoal:
        return const Color(0xFF111111);
      case DrawingBrushType.eraser:
        return Colors.white;
    }
  }
}

Map<DrawingBrushType, double> _buildInitialBrushWidths(
  Map<DrawingBrushType, double>? overrides,
) {
  return <DrawingBrushType, double>{
    for (final brush in DrawingBrushType.values)
      brush: ((overrides?[brush] ?? brush.defaultWidth).clamp(0.006, 0.08))
          .toDouble(),
  };
}

Map<DrawingBrushType, double> _buildInitialBrushOpacities(
  Map<DrawingBrushType, double>? overrides,
) {
  return <DrawingBrushType, double>{
    for (final brush in DrawingBrushType.values)
      brush: ((overrides?[brush] ?? brush.defaultOpacity).clamp(0.2, 1.0))
          .toDouble(),
  };
}

class DrawingStroke {
  final List<Offset> normalizedPoints;
  final DrawingBrushType brushType;
  final Color color;
  final double normalizedWidth;
  final double opacity;

  const DrawingStroke({
    required this.normalizedPoints,
    required this.brushType,
    required this.color,
    required this.normalizedWidth,
    required this.opacity,
  });

  bool get isEraser => brushType == DrawingBrushType.eraser;

  DrawingStroke copyWith({
    List<Offset>? normalizedPoints,
    DrawingBrushType? brushType,
    Color? color,
    double? normalizedWidth,
    double? opacity,
  }) {
    return DrawingStroke(
      normalizedPoints: normalizedPoints ?? this.normalizedPoints,
      brushType: brushType ?? this.brushType,
      color: color ?? this.color,
      normalizedWidth: normalizedWidth ?? this.normalizedWidth,
      opacity: opacity ?? this.opacity,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'brushType': brushType.name,
      'color': color.toARGB32(),
      'normalizedWidth': normalizedWidth,
      'opacity': opacity,
      'points': normalizedPoints
          .map((point) => <String, double>{'x': point.dx, 'y': point.dy})
          .toList(),
    };
  }

  factory DrawingStroke.fromJson(Map<String, dynamic> json) {
    final brushName =
        json['brushType'] as String? ?? DrawingBrushType.pencil.name;
    final brushType = DrawingBrushType.values.firstWhere(
      (value) => value.name == brushName,
      orElse: () => DrawingBrushType.pencil,
    );
    final pointsJson = (json['points'] as List<dynamic>? ?? const <dynamic>[]);

    return DrawingStroke(
      normalizedPoints: pointsJson
          .map((point) => Offset(
                ((point as Map<String, dynamic>)['x'] as num?)?.toDouble() ?? 0,
                (point['y'] as num?)?.toDouble() ?? 0,
              ))
          .toList(),
      brushType: brushType,
      color:
          Color((json['color'] as num?)?.toInt() ?? brushType.color.toARGB32()),
      normalizedWidth: (json['normalizedWidth'] as num?)?.toDouble() ??
          brushType.defaultWidth,
      opacity:
          (json['opacity'] as num?)?.toDouble() ?? brushType.defaultOpacity,
    );
  }
}

class DrawingController extends ChangeNotifier {
  DrawingController({
    Iterable<DrawingStroke> initialStrokes = const <DrawingStroke>[],
    DrawingBrushType initialBrush = DrawingBrushType.none,
    Map<DrawingBrushType, double>? initialBrushWidths,
    Map<DrawingBrushType, double>? initialBrushOpacities,
  })  : _strokes = List<DrawingStroke>.from(initialStrokes),
        _selectedBrush = initialBrush,
        _brushWidths = _buildInitialBrushWidths(initialBrushWidths),
        _brushOpacities = _buildInitialBrushOpacities(initialBrushOpacities);

  final List<DrawingStroke> _strokes;
  DrawingStroke? _activeStroke;
  DrawingBrushType _selectedBrush;
  final Map<DrawingBrushType, double> _brushWidths;
  final Map<DrawingBrushType, double> _brushOpacities;
  int _contentVersion = 0;

  UnmodifiableListView<DrawingStroke> get strokes =>
      UnmodifiableListView<DrawingStroke>(_strokes);

  DrawingStroke? get activeStroke => _activeStroke;

  DrawingBrushType get selectedBrush => _selectedBrush;

  bool get canDraw => _selectedBrush != DrawingBrushType.none;

  double get currentOpacity => _brushOpacities[_selectedBrush]!;

  double get currentWidth => _brushWidths[_selectedBrush]!;

  bool get hasCommittedStrokes => _strokes.isNotEmpty;

  int get contentVersion => _contentVersion;

  void selectBrush(DrawingBrushType brush) {
    if (_selectedBrush == brush) {
      return;
    }
    _selectedBrush = brush;
    notifyListeners();
  }

  void setOpacity(double opacity) {
    final normalizedOpacity = opacity.clamp(0.2, 1.0);
    if ((currentOpacity - normalizedOpacity).abs() < 0.001) {
      return;
    }
    _brushOpacities[_selectedBrush] = normalizedOpacity.toDouble();
    notifyListeners();
  }

  void setBrushWidth(double width) {
    final normalizedWidth = width.clamp(0.006, 0.08);
    if ((currentWidth - normalizedWidth).abs() < 0.0005) {
      return;
    }
    _brushWidths[_selectedBrush] = normalizedWidth.toDouble();
    notifyListeners();
  }

  void startStroke(Offset point) {
    if (!canDraw) {
      return;
    }
    _activeStroke = DrawingStroke(
      normalizedPoints: <Offset>[point],
      brushType: _selectedBrush,
      color: _selectedBrush.color,
      normalizedWidth: currentWidth,
      opacity: currentOpacity,
    );
    notifyListeners();
  }

  void appendPoint(Offset point) {
    final activeStroke = _activeStroke;
    if (activeStroke == null) {
      return;
    }

    final points = activeStroke.normalizedPoints;
    if (points.isNotEmpty && (points.last - point).distanceSquared < 0.000002) {
      return;
    }

    points.add(point);
    notifyListeners();
  }

  void endStroke() {
    final activeStroke = _activeStroke;
    if (activeStroke == null) {
      return;
    }

    _strokes.add(activeStroke);
    _activeStroke = null;
    _contentVersion += 1;
    notifyListeners();
  }

  void undo() {
    if (_strokes.isEmpty) {
      return;
    }

    _strokes.removeLast();
    _contentVersion += 1;
    notifyListeners();
  }

  void clear() {
    if (_strokes.isEmpty && _activeStroke == null) {
      return;
    }

    _strokes.clear();
    _activeStroke = null;
    _contentVersion += 1;
    notifyListeners();
  }

  Map<String, dynamic> toEditorData() {
    return <String, dynamic>{
      'selectedBrush': _selectedBrush.name,
      'brushSettings': <String, dynamic>{
        for (final brush in DrawingBrushType.values)
          brush.name: <String, dynamic>{
            'width': _brushWidths[brush],
            'opacity': _brushOpacities[brush],
          },
      },
      'strokes': _strokes.map((stroke) => stroke.toJson()).toList(),
    };
  }
}

class DrawingCanvas extends StatelessWidget {
  final DrawingController controller;
  final Color backgroundColor;

  const DrawingCanvas({
    super.key,
    required this.controller,
    required this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _DrawingPainter(
          controller: controller,
          backgroundColor: backgroundColor,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _DrawingPainter extends CustomPainter {
  final DrawingController controller;
  final Color backgroundColor;

  _DrawingPainter({
    required this.controller,
    required this.backgroundColor,
  }) : super(repaint: controller);

  @override
  void paint(Canvas canvas, Size size) {
    _paintDrawing(
      canvas: canvas,
      size: size,
      strokes: controller.strokes,
      activeStroke: controller.activeStroke,
      backgroundColor: backgroundColor,
    );
  }

  @override
  bool shouldRepaint(covariant _DrawingPainter oldDelegate) {
    return oldDelegate.controller != controller ||
        oldDelegate.backgroundColor != backgroundColor;
  }
}

void _paintDrawing({
  required Canvas canvas,
  required Size size,
  required List<DrawingStroke> strokes,
  required DrawingStroke? activeStroke,
  required Color backgroundColor,
}) {
  final backgroundPaint = Paint()..color = backgroundColor;
  canvas.drawRect(Offset.zero & size, backgroundPaint);

  for (final stroke in <DrawingStroke>[
    ...strokes,
    if (activeStroke != null) activeStroke
  ]) {
    _paintStroke(canvas, size, stroke, backgroundColor);
  }
}

void _paintStroke(
  Canvas canvas,
  Size size,
  DrawingStroke stroke,
  Color backgroundColor,
) {
  if (stroke.normalizedPoints.isEmpty) {
    return;
  }

  final paint = Paint()
    ..color = (stroke.isEraser ? backgroundColor : stroke.color)
        .withValues(alpha: stroke.opacity)
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke
    ..strokeWidth = stroke.normalizedWidth * size.shortestSide;

  final points = stroke.normalizedPoints
      .map((point) => Offset(point.dx * size.width, point.dy * size.height))
      .toList();

  if (points.length == 1) {
    canvas.drawCircle(
        points.first, paint.strokeWidth / 2, paint..style = PaintingStyle.fill);
    return;
  }

  final path = Path()..moveTo(points.first.dx, points.first.dy);
  for (var i = 1; i < points.length; i += 1) {
    final previous = points[i - 1];
    final current = points[i];
    final midpoint = Offset(
      (previous.dx + current.dx) / 2,
      (previous.dy + current.dy) / 2,
    );
    path.quadraticBezierTo(previous.dx, previous.dy, midpoint.dx, midpoint.dy);
  }
  path.lineTo(points.last.dx, points.last.dy);
  canvas.drawPath(path, paint);
}

Future<Uint8List> exportDrawingAsPng({
  required List<DrawingStroke> strokes,
  required Color backgroundColor,
  int dimension = 1024,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final size = Size.square(dimension.toDouble());

  _paintDrawing(
    canvas: canvas,
    size: size,
    strokes: strokes,
    activeStroke: null,
    backgroundColor: backgroundColor,
  );

  final image = await recorder.endRecording().toImage(dimension, dimension);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  if (bytes == null) {
    throw StateError('Failed to export drawing.');
  }

  return bytes.buffer.asUint8List();
}
