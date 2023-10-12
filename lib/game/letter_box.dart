import 'package:flutter/material.dart';
import 'package:operation_hermes/game/letter_box_data.dart';
import 'package:operation_hermes/game/letter_box_state.dart';

class LetterBox extends StatefulWidget {
  const LetterBox({super.key, required this.data});

  final LetterBoxData data;

  @override
  State<LetterBox> createState() => _LetterBoxState();
}

class _LetterBoxState extends State<LetterBox> {
  final animationDuration = 250;

  @override
  Widget build(BuildContext context) {
    print("Building ${widget.data.letter}");

    Color getContainerColor() {
      switch (widget.data.state) {
        case LetterBoxState.solutionSlot:
          return Theme.of(context).colorScheme.secondaryContainer.withOpacity(0.25);
        case LetterBoxState.solutionPick:
          return Theme.of(context).colorScheme.surfaceVariant;
        case LetterBoxState.fieldPick:
          return Theme.of(context).colorScheme.primaryContainer;
        case LetterBoxState.fieldSlot:
          return Theme.of(context).colorScheme.secondaryContainer.withOpacity(0.25);
        case LetterBoxState.locked:
          return Theme.of(context).colorScheme.tertiaryContainer;
        case LetterBoxState.removed:
          return Theme.of(context).colorScheme.secondaryContainer.withOpacity(0.1);
      }
    }

    Color getContainerBorderColor() {
      switch (widget.data.state) {
        case LetterBoxState.solutionSlot:
          return Theme.of(context).colorScheme.onSecondaryContainer.withOpacity(0.5);
        case LetterBoxState.solutionPick:
          return Theme.of(context)
              .colorScheme
              .onSurfaceVariant;
        case LetterBoxState.fieldPick:
          return Theme.of(context)
              .colorScheme
              .onPrimaryContainer
              .withOpacity(0.5);
        case LetterBoxState.fieldSlot:
          return Theme.of(context).colorScheme.onSecondaryContainer.withOpacity(0.5);
        case LetterBoxState.removed:
          return Theme.of(context).colorScheme.onSurface.withOpacity(0.1);
        case LetterBoxState.locked:
          return Theme.of(context)
              .colorScheme
              .onTertiaryContainer
              .withOpacity(0.5);
      }
    }

    Color getTextColor() {
      switch (widget.data.state) {
        case LetterBoxState.solutionSlot:
          return Colors.transparent;
        case LetterBoxState.solutionPick:
          return Theme.of(context).colorScheme.onSurfaceVariant;
        case LetterBoxState.fieldPick:
          return Theme.of(context).colorScheme.onPrimaryContainer;
        case LetterBoxState.fieldSlot:
          return Theme.of(context).colorScheme.onSurfaceVariant;
        case LetterBoxState.locked:
          return Theme.of(context).colorScheme.onTertiaryContainer;
        case LetterBoxState.removed:
          return Theme.of(context).colorScheme.secondary.withOpacity(0.1);
      }
    }

    Curve getCurve() {
      switch (widget.data.state) {
        case LetterBoxState.solutionSlot:
          return Curves.easeIn;
        case LetterBoxState.solutionPick:
          return Curves.easeOut;
        case LetterBoxState.fieldPick:
          return Curves.easeOut;
        case LetterBoxState.fieldSlot:
          return Curves.easeIn;
        case LetterBoxState.locked:
          return Curves.easeInOut;
        case LetterBoxState.removed:
          return Curves.easeInOut;
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
        case LetterBoxState.locked:
          return fontSize;
        case LetterBoxState.removed:
          return fontSize;
      }
    }

    return LimitedBox(
      maxHeight: 55,
      child: AspectRatio(
        aspectRatio: 1 / 1,
        child: AnimatedContainer(
          transformAlignment: Alignment.center,
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
          duration: Duration(milliseconds: animationDuration),
          margin: const EdgeInsets.all(2.0),
          child: LayoutBuilder(
            builder: (context, constraints) {
              double fontSize = constraints.maxHeight * 0.6;
              return Center(
                child: AnimatedDefaultTextStyle(
                  style: TextStyle(
                      fontFamily: DefaultTextStyle.of(context).style.fontFamily,
                      color: getTextColor(),
                      fontSize: getFontSize(fontSize)),
                  duration: Duration(milliseconds: animationDuration),
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
