import 'package:flutter/material.dart';

class StoryCard extends StatelessWidget {
  const StoryCard({super.key, required this.text});

  final List<WidgetSpan> text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Card(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: RichText(
              text: TextSpan(children: text),
              textAlign: TextAlign.justify,
            ),
          ),
        ),
      ),
    );
  }
}
