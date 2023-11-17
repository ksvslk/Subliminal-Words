import 'dart:math';

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';

class Confetti extends StatefulWidget {
  const Confetti({super.key, required this.startConfetti});

  final bool startConfetti;

  @override
  State<Confetti> createState() => _ConfettiState();
}

class _ConfettiState extends State<Confetti> {
  late ConfettiController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ConfettiController(duration: const Duration(seconds: 10));
    _controller.play();
  }

  @override
  void dispose() {
    super.dispose();
    _controller.dispose();
  }

  Path createCirclePathFromSize(Size size) {
    Path path = Path();

    // Calculate the center of the given size
    Offset center = Offset(size.width / 2, size.height / 2);

    // Set the radius to half of the smaller dimension (width or height)
    double radius = size.shortestSide / 2;

    // Add a circular path to the path object
    path.addOval(Rect.fromCircle(center: center, radius: radius));

    return path;
  }

  Path drawStar(Size size) {
    // Method to convert degree to radians
    double degToRad(double deg) => deg * (pi / 180.0);

    const numberOfPoints = 5;
    final halfWidth = size.width / 2;
    final externalRadius = halfWidth;
    final internalRadius = halfWidth / 2.5;
    final degreesPerStep = degToRad(360 / numberOfPoints);
    final halfDegreesPerStep = degreesPerStep / 2;
    final path = Path();
    final fullAngle = degToRad(360);
    path.moveTo(size.width, halfWidth);

    for (double step = 0; step < fullAngle; step += degreesPerStep) {
      path.lineTo(halfWidth + externalRadius * cos(step),
          halfWidth + externalRadius * sin(step));
      path.lineTo(halfWidth + internalRadius * cos(step + halfDegreesPerStep),
          halfWidth + internalRadius * sin(step + halfDegreesPerStep));
    }
    path.close();
    return path;
  }

  @override
  Widget build(BuildContext context) {
    return widget.startConfetti
        ? SafeArea(
            child: Container(
              color: Theme.of(context).colorScheme.background,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "Game complete!",
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onBackground,
                        fontSize: Theme.of(context)
                            .textTheme
                            .headlineLarge
                            ?.fontSize),
                  ),
                  Align(
                    alignment: Alignment.topCenter,
                    child: ConfettiWidget(
                      confettiController: _controller,
                      maxBlastForce: 20,
                      minBlastForce: 10,
                      numberOfParticles: 1,
                      gravity: 0.1,
                      minimumSize: const Size(20, 20),
                      maximumSize: const Size(150, 150),
                      blastDirection: -90 * (pi / 180.0),
                      blastDirectionality: BlastDirectionality.directional,
                      shouldLoop:
                          true, // start again as soon as the animation is finished
                      colors: const [
                        Color.fromARGB(255, 255, 0, 0),
                        Color.fromARGB(255, 255, 174, 0),
                        Color.fromARGB(255, 255, 247, 0),
                      ], // manually specify the colors to be used
                      createParticlePath: drawStar,
                    ),
                  ),
                ],
              ),
            ),
          )
        : const SizedBox.shrink();
  }
}
