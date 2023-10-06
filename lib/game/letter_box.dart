import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:operation_hermes/game/letter_box_state.dart';

typedef LetterData = ({int index, String letter, LetterBoxState state});

class LetterBox extends StatelessWidget {
  const LetterBox(
      {super.key,
      this.callback,
      required this.data});

  final bool Function(LetterData)? callback;
  final LetterData data;

  @override
  Widget build(BuildContext context) {

    Color getContainerColor() {
      switch (data.state) {
        case LetterBoxState.slot:
          return Theme.of(context).colorScheme.secondaryContainer;
        case LetterBoxState.placed:
          return Theme.of(context).colorScheme.primaryContainer;
        case LetterBoxState.pick:
          return Theme.of(context).colorScheme.primaryContainer;
        case LetterBoxState.chosen:
          return Theme.of(context).colorScheme.background;
        case LetterBoxState.gone:
          return Colors.transparent;
      }
    }

    Color getTextColor() {
      switch (data.state) {
        case LetterBoxState.slot:
          return Colors.transparent;
        case LetterBoxState.placed:
          return Theme.of(context).colorScheme.onPrimaryContainer;
        case LetterBoxState.pick:
          return Theme.of(context).colorScheme.onPrimaryContainer;
        case LetterBoxState.chosen:
          return Colors.transparent;
        case LetterBoxState.gone:
          return Colors.transparent;
      }
    }

   int getDuration() {
      switch (data.state) {
        case LetterBoxState.slot:
          return 200;
        case LetterBoxState.placed:
          return 200;
        case LetterBoxState.pick:
          return 200;
        case LetterBoxState.chosen:
          return 300;
        case LetterBoxState.gone:
          return 200;
      }
    }

      Curve getCurve() {
      switch (data.state) {
        case LetterBoxState.slot:
          return Curves.easeIn;
        case LetterBoxState.placed:
          return Curves.easeOutSine;
        case LetterBoxState.pick:
          return Curves.easeOut;
        case LetterBoxState.chosen:
          return Curves.easeIn;
        case LetterBoxState.gone:
          return Curves.easeIn;
      }
    }

    Color getContainerBorderColor() {
      switch (data.state) {
        case LetterBoxState.pick:
          return Theme.of(context).colorScheme.primary;
        case LetterBoxState.slot:
          return Theme.of(context).colorScheme.outline;
        case LetterBoxState.placed:
          return Theme.of(context).colorScheme.secondary;
        case LetterBoxState.chosen || LetterBoxState.gone:
          return Colors.transparent;
      }
    }

    Matrix4 getContainerTransformMatrix() {
    switch (data.state) {
        case LetterBoxState.slot:
          return Matrix4.identity();
        case LetterBoxState.placed:
          return Matrix4.identity();
        case LetterBoxState.pick:
          return Matrix4.identity();
        case LetterBoxState.chosen:
          return Matrix4.identity()..scale(0.25, 0.25);
        case LetterBoxState.gone:
          return Matrix4.identity()..scale(0.25, 0.25);
      }
    }

    return GestureDetector(
      onTap: () {
        var result = callback?.call(data);
        if (result == true) {
          HapticFeedback.selectionClick();
        }
      },
      child: LimitedBox(
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
                    0.5; // half of the container's height
                return Center(
                  child: AnimatedDefaultTextStyle(
                    style: TextStyle(
                      fontFamily: DefaultTextStyle.of(context).style.fontFamily,
                      color: getTextColor(),
                      fontSize: (data.state == LetterBoxState.placed ||
                              data.state == LetterBoxState.pick)
                          ? fontSize
                          : fontSize / 3,
                    ),
                    duration: Duration(milliseconds: getDuration()),
                    curve: getCurve(),
                    child: Text(data.letter),
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
