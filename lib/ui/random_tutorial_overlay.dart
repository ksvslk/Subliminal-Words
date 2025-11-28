import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:math';

class RandomTutorialOverlay extends StatefulWidget {
  final String tutorialId;
  final Widget child;
  final String hintText;
  final GlobalKey clueKey;      
  final GlobalKey playZoneKey;  
  
  const RandomTutorialOverlay({
    Key? key,
    required this.tutorialId,
    required this.child,
    required this.hintText,
    required this.clueKey,
    required this.playZoneKey,
  }) : super(key: key);

  @override
  _RandomTutorialOverlayState createState() => _RandomTutorialOverlayState();
}

class _RandomTutorialOverlayState extends State<RandomTutorialOverlay> {
  bool _isVisible = false;
  int _step = 0; 
  
  // --- Spotlight Variables ---
  Rect? _spotlightRect;
  BoxShape _spotlightShape = BoxShape.circle;

  // --- Step 1 Specifics ---
  double? _textBoxY; 
  Offset? _arrowEnd;

  // --- Step 2 Specifics ---
  Offset? _handPosition;
  Timer? _handTimer;
  final Random _rnd = Random();

  @override
  void initState() {
    super.initState();
    _checkPrefs();
  }

  @override
  void dispose() {
    _handTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final bool seen = prefs.getBool(widget.tutorialId) ?? false; 

    if (!seen || true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startStep1(MediaQuery.of(context));
      });
    }
  }

  void _startStep1(MediaQueryData mediaQuery) {
    final renderBox = widget.clueKey.currentContext?.findRenderObject() as RenderBox?;
    
    if (renderBox != null) {
      final position = renderBox.localToGlobal(Offset.zero);
      final size = renderBox.size;
      
      setState(() {
        _isVisible = true;
        _step = 1;
        
        _spotlightRect = Rect.fromLTWH(
          position.dx - 10, 
          position.dy - 10, 
          size.width + 20, 
          size.height + 20
        );
        _spotlightShape = BoxShape.circle;
        _arrowEnd = _spotlightRect!.center;

        double calculatedY = position.dy + size.height + 60;
        if (calculatedY + 120 > mediaQuery.size.height) {
           calculatedY = position.dy - 130; 
        }
        _textBoxY = calculatedY;
      });
    }
  }

  void _startStep2() {
    final renderBox = widget.playZoneKey.currentContext?.findRenderObject() as RenderBox?;
    
    if (renderBox != null) {
      final position = renderBox.localToGlobal(Offset.zero);
      final size = renderBox.size;

      setState(() {
        _step = 2;
        
        _spotlightRect = Rect.fromLTWH(
          position.dx - 10, 
          position.dy - 10, 
          size.width + 20, 
          size.height + 20
        );
        _spotlightShape = BoxShape.rectangle; 
      });

      _moveHandRandomly();
      // Keep moving every 600ms
      _handTimer = Timer.periodic(const Duration(milliseconds: 600), (timer) {
        _moveHandRandomly();
      });
    }
  }

  void _moveHandRandomly() {
    if (_spotlightRect == null) return;
    
    final double centerX = _spotlightRect!.center.dx;
    final double centerY = _spotlightRect!.center.dy;
    final double maxRadius = (_spotlightRect!.shortestSide / 2) * 0.7; 
    const double iconOffset = 40.0; 
    
    // --- UPDATED LOGIC: Minimum Movement 55px ---
    const double minMoveDistance = 55.0; 
    
    Offset? nextPos;
    int attempts = 0;

    // Retry loop: try up to 10 times to find a point far enough away
    do {
      final double angle = _rnd.nextDouble() * 2 * pi; 
      final double radius = _rnd.nextDouble() * maxRadius; 

      final double candidateX = centerX + (cos(angle) * radius);
      final double candidateY = centerY + (sin(angle) * radius);
      final Offset candidate = Offset(candidateX, candidateY);

      if (_handPosition == null) {
        // First move, accept anything
        nextPos = candidate;
      } else {
        // Calculate distance from current actual finger center
        // (We add iconOffset back to compare center-to-center)
        final Offset currentCenter = _handPosition! + const Offset(iconOffset, iconOffset);
        final double distance = (candidate - currentCenter).distance;

        if (distance >= minMoveDistance) {
          nextPos = candidate;
        }
      }
      attempts++;
    } while (nextPos == null && attempts < 10);

    // If we couldn't find a far enough point (box too small?), just take the last candidate
    if (nextPos == null) {
       // Just regenerate one last time without check
       final double angle = _rnd.nextDouble() * 2 * pi; 
       final double radius = _rnd.nextDouble() * maxRadius; 
       nextPos = Offset(centerX + (cos(angle) * radius), centerY + (sin(angle) * radius));
    }

    setState(() {
      _handPosition = nextPos! - const Offset(iconOffset, iconOffset);
    });
  }

  Future<void> _dismiss() async {
    setState(() => _isVisible = false);
    _handTimer?.cancel();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(widget.tutorialId, true);
  }

  void _onTap() {
    if (_step == 1) {
      _startStep2();
    } else if (_step == 2) {
      _dismiss();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final Color overlayColor = colorScheme.scrim;
    
    // Hand Colors
    final Color handFillColor = colorScheme.surface; 
    final Color handBorderColor = colorScheme.onSurface; 

    // Arrow Colors
    final Color arrowFillColor = colorScheme.primary;
    final Color arrowBorderColor = colorScheme.surface;

    return Stack(
      children: [
        widget.child,

        if (_isVisible && _spotlightRect != null)
          GestureDetector(
            onTap: _onTap,
            child: Stack(
              children: [
                // 1. SPOTLIGHT PAINTER
                Positioned.fill(
                  child: CustomPaint(
                    painter: SpotlightPainter(
                      targetRect: _spotlightRect!,
                      shape: _spotlightShape,
                      overlayColor: overlayColor,
                      opacity: 0.85, 
                    ),
                  ),
                ),

                // --- STEP 1: ARROW & TEXT ---
                if (_step == 1 && _arrowEnd != null && _textBoxY != null)
                  Stack(
                    children: [
                      // Text Box
                      Positioned(
                        top: _textBoxY!,
                        left: 20, right: 20,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                            decoration: BoxDecoration(
                              color: colorScheme.surface, 
                              borderRadius: BorderRadius.circular(30),
                              border: Border.all(
                                color: colorScheme.primary, 
                                width: 3
                              ),
                              boxShadow: [
                                BoxShadow(
                                    color: colorScheme.shadow.withOpacity(0.3),
                                    blurRadius: 15,
                                    offset: const Offset(0, 8))
                              ],
                            ),
                            child: Text(
                              widget.hintText,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onSurface 
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Arrow
                      Positioned.fill(
                        child: LayoutBuilder(
                          builder: (ctx, constraints) {
                            final startPoint = Offset(constraints.maxWidth / 2, _textBoxY!);
                            return CustomPaint(
                              painter: ModernArrowPainter(
                                startPoint: startPoint,
                                endPoint: _arrowEnd!,
                                color: arrowFillColor,
                                borderColor: arrowBorderColor,
                              ),
                            );
                          }
                        ),
                      ),
                    ],
                  ),

                // --- STEP 2: HAND ---
                if (_step == 2 && _handPosition != null)
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeInOut,
                    left: _handPosition!.dx,
                    top: _handPosition!.dy,
                    child: IgnorePointer(
                      child: Icon(
                        Icons.touch_app, 
                        size: 80, 
                        color: handFillColor,
                        shadows: List.generate(8, (index) {
                          double angle = (index * pi * 2) / 8;
                          return Shadow(
                            offset: Offset(cos(angle) * 3, sin(angle) * 3), 
                            color: handBorderColor,
                            blurRadius: 0,
                          );
                        }),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

// --- PAINTERS ---

class SpotlightPainter extends CustomPainter {
  final Rect targetRect;
  final BoxShape shape;
  final double opacity;
  final Color overlayColor;

  SpotlightPainter({
    required this.targetRect,
    required this.shape,
    required this.overlayColor,
    this.opacity = 0.85,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawColor(overlayColor.withOpacity(opacity), BlendMode.srcOver);

    final Paint eraser = Paint()..blendMode = BlendMode.dstOut;
    eraser.maskFilter = const MaskFilter.blur(BlurStyle.normal, 15);

    if (shape == BoxShape.circle) {
      final center = targetRect.center;
      final radius = max(targetRect.width, targetRect.height) / 2;
      canvas.drawCircle(center, radius, eraser);
    } else {
      canvas.drawRRect(
        RRect.fromRectAndRadius(targetRect, const Radius.circular(16)), 
        eraser
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant SpotlightPainter oldDelegate) => 
      oldDelegate.targetRect != targetRect || oldDelegate.shape != shape;
}

class ModernArrowPainter extends CustomPainter {
  final Offset startPoint;
  final Offset endPoint;
  final Color color;
  final Color borderColor;

  ModernArrowPainter({
    required this.startPoint, 
    required this.endPoint, 
    required this.color,
    required this.borderColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const double mainWidth = 6.0;
    const double borderWidth = 10.0;
    const double arrowHeadLength = 30.0;
    const double arrowHeadAngle = pi / 7;

    void drawLayer(double strokeWidth, Color drawColor) {
      final paint = Paint()
        ..color = drawColor
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      canvas.drawLine(startPoint, endPoint, paint);

      final dotPaint = Paint()
        ..color = drawColor
        ..style = PaintingStyle.fill;
      canvas.drawCircle(startPoint, strokeWidth + 2, dotPaint);

      final angle = atan2(endPoint.dy - startPoint.dy, endPoint.dx - startPoint.dx);
      final arrowPath = Path()
        ..moveTo(endPoint.dx, endPoint.dy)
        ..lineTo(
          endPoint.dx - arrowHeadLength * cos(angle - arrowHeadAngle),
          endPoint.dy - arrowHeadLength * sin(angle - arrowHeadAngle),
        )
        ..moveTo(endPoint.dx, endPoint.dy)
        ..lineTo(
          endPoint.dx - arrowHeadLength * cos(angle + arrowHeadAngle),
          endPoint.dy - arrowHeadLength * sin(angle + arrowHeadAngle),
        );
      
      paint.style = PaintingStyle.stroke;
      canvas.drawPath(arrowPath, paint);
    }

    drawLayer(borderWidth, borderColor);
    drawLayer(mainWidth, color);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}