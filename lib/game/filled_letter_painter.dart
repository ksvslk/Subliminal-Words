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
    const mainColor =  Color.fromRGBO(254, 89, 194, 1.0);
    var scale = size.width / 512;
    canvas.scale(scale,scale);

    // Base stroke
    final Paint neonBase = Paint()
      ..color = mainColor.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Glow
    final Paint neonGlow = Paint()
      ..color = mainColor.withOpacity(0.5)  // Adjust opacity for desired glow intensity
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.0  // Adjust for desired glow spread
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);  // Blur to soften the glow edges

    // Draw the glow first
    canvas.drawPath(path, neonGlow);

    // Draw the main stroke/path on top of the glow
    canvas.drawPath(path, neonBase);
  }
}