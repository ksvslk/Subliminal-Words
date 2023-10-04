import 'package:flutter/material.dart';

class LetterBox extends StatelessWidget {
  final String letter;
  final double maxSize = 55.0; // Maximum size for the LetterBox

  const LetterBox({super.key, required this.letter});

  @override
  Widget build(BuildContext context) {
    return Flexible(
      fit: FlexFit.loose,
      child: LimitedBox(
        maxHeight: maxSize,
        child: AspectRatio(
          aspectRatio: 1 / 1,
          child: Container(
            color: Colors.blue,
            margin: const EdgeInsets.all(2.0),
            child: LayoutBuilder(
              builder: (context, constraints) {
                double fontSize = constraints.maxHeight *
                    0.5; // half of the container's height
                return Center(
                  child: Text(
                    letter,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: fontSize,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
