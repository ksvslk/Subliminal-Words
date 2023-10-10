import 'package:flutter/material.dart';
import 'package:operation_hermes/audio/audio_controller.dart';
import 'package:operation_hermes/audio/sounds.dart';
import 'package:operation_hermes/game/letter_box_data.dart';
import 'package:operation_hermes/game/letter_box_state.dart';
import 'package:provider/provider.dart';


class LetterBox extends StatefulWidget {
  const LetterBox({super.key, required this.data});

  final LetterBoxData data;

  @override
  State<LetterBox> createState() => _LetterBoxState();
}

class _LetterBoxState extends State<LetterBox> {

  @override
  Widget build(BuildContext context) {
    print("Building ${widget.data.letter}");

    Color getContainerColor() {
      switch (widget.data.state) {
        case LetterBoxState.solutionSlot:
          return Theme.of(context).colorScheme.secondaryContainer;
        case LetterBoxState.solutionPick:
          return Theme.of(context).colorScheme.tertiaryContainer;
        case LetterBoxState.fieldPick:
          return Theme.of(context).colorScheme.primaryContainer;
        case LetterBoxState.fieldSlot:
          return Theme.of(context).colorScheme.background;
      }
    }

    Color getTextColor() {
      switch (widget.data.state) {
        case LetterBoxState.solutionSlot:
          return Colors.transparent;
        case LetterBoxState.solutionPick:
          return Theme.of(context).colorScheme.onTertiaryContainer;
        case LetterBoxState.fieldPick:
          return Theme.of(context).colorScheme.onPrimaryContainer;
        case LetterBoxState.fieldSlot:
          return Theme.of(context).colorScheme.onSurfaceVariant;
      }
    }

    int getDuration() {
      return 300;
      /*
      switch (data.state) {
        case LetterBoxState.slot:
          return 100;
        case LetterBoxState.placed:
          return 50;
        case LetterBoxState.pick:
          return 100;
        case LetterBoxState.chosen:
          return 100;
        case LetterBoxState.gone:
          return 50;
      }
      */
    }

    Curve getCurve() {
      return Curves.bounceInOut;
      /*
      switch (data.state) {
        case LetterBoxState.slot:
          return Curves.bounceIn;
        case LetterBoxState.placed:
          return Curves.bounceInOut;
        case LetterBoxState.pick:
          return Curves.bounceInOut;
        case LetterBoxState.chosen:
          return Curves.bounceIn;
        case LetterBoxState.gone:
          return Curves.bounceIn;
      }
      */
    }

    Color getContainerBorderColor() {
      switch (widget.data.state) {
        case LetterBoxState.fieldPick:
          return Theme.of(context).colorScheme.primary;
        case LetterBoxState.solutionSlot:
          return Theme.of(context).colorScheme.outline;
        case LetterBoxState.solutionPick:
          return Theme.of(context).colorScheme.secondary;
        case LetterBoxState.fieldSlot:
          return Theme.of(context).colorScheme.outlineVariant;
      }
    }

    Matrix4 getContainerTransformMatrix() {
      return Matrix4.identity();
      switch (widget.data.state) {
        case LetterBoxState.solutionSlot:
          return Matrix4.identity();
        case LetterBoxState.solutionPick:
          return Matrix4.identity();
        case LetterBoxState.fieldPick:
          return Matrix4.identity();
        case LetterBoxState.fieldSlot:
          return Matrix4.identity()..scale(0.25, 0.25);
      }
    }

    double getFontSize(double fontSize) {
      switch (widget.data.state) {
        case LetterBoxState.solutionSlot:
          return 0.0;
        case LetterBoxState.solutionPick:
          return fontSize;
        case LetterBoxState.fieldPick:
          return fontSize;
        case LetterBoxState.fieldSlot:
          return 0.0;
      }
    }

    return LimitedBox(
        maxHeight: 55,
        child: AspectRatio(
          aspectRatio: 1 / 1,
          child: AnimatedContainer(
            transformAlignment: Alignment.center,
            transform: getContainerTransformMatrix(),
            decoration: ShapeDecoration(
              color: getContainerColor(),
              shape: RoundedRectangleBorder(
                borderRadius: const BorderRadius.all(
                  Radius.circular(4),
                ),
                side: BorderSide(
                  width: 2,
                  color: getContainerBorderColor(),
                ),
              ),
            ),
            duration: Duration(milliseconds: getDuration()),
            margin: const EdgeInsets.all(2.0),
            child: LayoutBuilder(
              builder: (context, constraints) {
                double fontSize = constraints.maxHeight *
                    0.6; // half of the container's height
                return Center(
                  child: AnimatedDefaultTextStyle(
                    style: TextStyle(
                      fontFamily: DefaultTextStyle.of(context).style.fontFamily,
                      color: getTextColor(),
                      fontSize: getFontSize(fontSize)
                    ),
                    duration: Duration(milliseconds: getDuration()),
                    curve: getCurve(),
                    child: Text(widget.data.letter),
                  ),
                );
              },
            ),
          ),
        ),
    );
  }
}
