import 'package:flutter/material.dart';

class FilledLetterPainter extends CustomPainter {
  const FilledLetterPainter({
    required this.path,
    required this.firstColor,
    required this.secondColor,
  });

  final Path path;
  final Color firstColor;
  final Color secondColor;

  @override
  bool shouldRepaint(FilledLetterPainter oldDelegate) =>
      oldDelegate.path != path || oldDelegate.firstColor != firstColor;

  @override
  void paint(Canvas canvas, Size size) {
    var scale = size.width / 1024;
    canvas.scale(scale,scale);

    // Base stroke
    final Paint neonBase = Paint()
      ..color = firstColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0;

    // Glow
    final Paint neonGlow = Paint()
      ..color = secondColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10.0);
    canvas.drawPath(path, neonGlow);
    canvas.drawPath(path, neonBase);
  }
}