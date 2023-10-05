import 'package:flutter/material.dart';
import 'package:operation_hermes/game/letter_box_state.dart';

class LetterBox extends StatefulWidget {
  const LetterBox(
      {super.key,
      required this.letter,
      this.state = LetterBoxState.empty,
      this.callback});

  final String letter;
  final LetterBoxState state;
  final VoidCallback? callback;

  @override
  State<LetterBox> createState() => _LetterBoxState();
}

class _LetterBoxState extends State<LetterBox> {
  late LetterBoxState _state;

  @override
  void initState() {
    super.initState();
    _state = widget.state;
  }

  void changeStateTo(LetterBoxState newState) {
    setState(() {
      _state = newState;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => changeStateTo(LetterBoxState.empty),
      child: LimitedBox(
          maxHeight: 55,
          child: AspectRatio(
            aspectRatio: 1 / 1,
            child: AnimatedContainer(
              decoration: ShapeDecoration(
                color: _state == LetterBoxState.letter
                    ? Theme.of(context).colorScheme.primaryContainer
                    : Theme.of(context).colorScheme.primaryContainer,
                shape: RoundedRectangleBorder(
                  borderRadius: const BorderRadius.all(
                    Radius.circular(4),
                  ),
                  side: BorderSide(
                    width: 2,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              duration: const Duration(milliseconds: 1000),
              margin: const EdgeInsets.all(2.0),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  double fontSize = constraints.maxHeight *
                      0.5; // half of the container's height
                  return Center(
                    child: AnimatedDefaultTextStyle(
                      style: TextStyle(
                        fontFamily: 'Gabarito',
                        color: _state == LetterBoxState.letter
                            ? Theme.of(context).colorScheme.onPrimaryContainer
                            : Colors.transparent,
                        fontSize: _state == LetterBoxState.letter
                            ? fontSize
                            : fontSize / 3,
                      ),
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeInCubic,
                      child: Text(
                        widget.letter
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
