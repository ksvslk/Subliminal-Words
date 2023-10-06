import 'package:flutter/material.dart';

class Puzzle extends StatefulWidget {
  const Puzzle({super.key, required this.picturePath});

  final String picturePath;

  @override
  State<Puzzle> createState() => _PuzzleState();
}

class _PuzzleState extends State<Puzzle> {
  @override
  Widget build(BuildContext context) {
    return Flexible(
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.secondary, width: 2),
          borderRadius: BorderRadius.circular(4),
        ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: Image.asset(
              widget.picturePath,
              fit: BoxFit.fill,
            ),
          ),
      ),
    );
  }
}
