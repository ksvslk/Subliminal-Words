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
      child: Flexible(
        fit: FlexFit.loose,
        child: LimitedBox(
          maxHeight: 55,
          child: AspectRatio(
            aspectRatio: 1 / 1,
            child: AnimatedContainer(
                duration: const Duration(milliseconds: 1000),
                color: _state == LetterBoxState.letter
                    ? Colors.blue
                    : Colors.blueGrey,
                margin: const EdgeInsets.all(2.0),
                child: LayoutBuilder(
                        builder: (context, constraints) {
                          double fontSize = constraints.maxHeight *
                              0.5; // half of the container's height
                          return Center(
                            child: AnimatedDefaultTextStyle(
                              style: TextStyle(
                                color: _state == LetterBoxState.letter ? Colors.white : Colors.transparent,
                                fontSize: _state == LetterBoxState.letter ? fontSize : fontSize / 3 ,
                              ),
                              duration: const Duration(milliseconds: 500),
                              child: Text(widget.letter),
                            ),
                          );
                        },
                      ),
                      ),
          ),
        ),
      ),
    );
  }
}
