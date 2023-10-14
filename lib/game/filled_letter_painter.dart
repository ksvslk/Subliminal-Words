import 'package:flutter/material.dart';

class FilledLetterPainter extends CustomPainter {
  const FilledLetterPainter({
    required this.path,
    required this.color,
  });

  final Path path;
  final Color color;

  @override
  bool shouldRepaint(FilledLetterPainter oldDelegate) =>
      oldDelegate.path != path || oldDelegate.color != color;

  @override
  void paint(Canvas canvas, Size size) {
    var scale = size.width / 512;
    canvas.scale(scale,scale);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 4.0
        ..style = PaintingStyle.stroke,
    );
  }
}