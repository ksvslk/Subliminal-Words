import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:operation_hermes/data/word_letter_style.dart';

class FilledLetterPainter extends CustomPainter {
  const FilledLetterPainter({
    this.path,
    this.text,
    this.center,
    this.fontSize = 132,
    this.rotationDegrees = 0,
    this.scaleX = 1,
    this.scaleY = 1,
    this.skewXDegrees = 0,
    this.skewYDegrees = 0,
    this.opacity = 1,
    this.fontWeightValue = kDefaultWordLetterWeightValue,
    required this.firstColor,
    required this.secondColor,
  });

  final Path? path;
  final String? text;
  final Offset? center;
  final double fontSize;
  final double rotationDegrees;
  final double scaleX;
  final double scaleY;
  final double skewXDegrees;
  final double skewYDegrees;
  final double opacity;
  final int fontWeightValue;
  final Color firstColor;
  final Color secondColor;

  @override
  bool shouldRepaint(FilledLetterPainter oldDelegate) =>
      oldDelegate.path != path ||
      oldDelegate.text != text ||
      oldDelegate.center != center ||
      oldDelegate.fontSize != fontSize ||
      oldDelegate.rotationDegrees != rotationDegrees ||
      oldDelegate.scaleX != scaleX ||
      oldDelegate.scaleY != scaleY ||
      oldDelegate.skewXDegrees != skewXDegrees ||
      oldDelegate.skewYDegrees != skewYDegrees ||
      oldDelegate.opacity != opacity ||
      oldDelegate.fontWeightValue != fontWeightValue ||
      oldDelegate.firstColor != firstColor ||
      oldDelegate.secondColor != secondColor;

  @override
  void paint(Canvas canvas, Size size) {
    var scale = size.width / 1024;
    canvas.scale(scale, scale);
    final baseStrokeWidth = wordLetterPainterBaseStrokeWidth(fontWeightValue);
    final glowStrokeWidth = wordLetterPainterGlowStrokeWidth(fontWeightValue);

    final glyphPath = path;
    if (glyphPath != null) {
      final Paint neonBase = Paint()
        ..color = firstColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6.0;

      final Paint neonGlow = Paint()
        ..color = secondColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10.0);
      canvas.drawPath(glyphPath, neonGlow);
      canvas.drawPath(glyphPath, neonBase);
      return;
    }

    final glyphText = text;
    final glyphCenter = center;
    if (glyphText == null || glyphCenter == null || glyphText.isEmpty) {
      return;
    }

    canvas.save();
    canvas.translate(glyphCenter.dx, glyphCenter.dy);
    canvas.rotate(rotationDegrees * 3.1415926535897932 / 180);
    final transform = Matrix4.identity()
      ..setEntry(0, 1, math.tan(skewXDegrees * math.pi / 180))
      ..setEntry(1, 0, math.tan(skewYDegrees * math.pi / 180));
    transform.scaleByDouble(
      scaleX * wordLetterWidthScale(fontWeightValue),
      scaleY,
      1,
      1,
    );
    canvas.transform(transform.storage);

    final glowStyle = TextStyle(
      fontSize: fontSize,
      fontWeight: wordLetterFontWeight(fontWeightValue),
      foreground: Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = glowStrokeWidth
        ..color = secondColor.withValues(alpha: opacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0),
    );
    final baseStyle = TextStyle(
      fontSize: fontSize,
      fontWeight: wordLetterFontWeight(fontWeightValue),
      foreground: Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = baseStrokeWidth
        ..color = firstColor.withValues(alpha: opacity),
    );

    final glowPainter = TextPainter(
      text: TextSpan(text: glyphText, style: glowStyle),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();
    final basePainter = TextPainter(
      text: TextSpan(text: glyphText, style: baseStyle),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();

    final offset = Offset(
      -glowPainter.width / 2,
      -glowPainter.height / 2,
    );
    glowPainter.paint(canvas, offset);
    basePainter.paint(canvas, offset);
    canvas.restore();
  }
}
