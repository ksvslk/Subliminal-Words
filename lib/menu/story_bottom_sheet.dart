import 'dart:ui';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

class StoryBottomSheet extends StatelessWidget {
  const StoryBottomSheet({super.key});
  final testLimit = 4;
  @override
  Widget build(BuildContext context) {
    String text =
        'The value will provided in fontFamily will act as';
    List<String> words = text.split(' ');
    List<WidgetSpan> spans = words.mapIndexed((index, word) {
      return WidgetSpan(
          child: Container(
              margin: const EdgeInsets.symmetric(vertical: 2.0),
              padding: const EdgeInsets.symmetric(horizontal: 6.0),
              decoration: BoxDecoration(
                  border: Border.all(color: Colors.transparent),
                  color: word == 'will'
                      ? (index < testLimit
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context)
                              .colorScheme
                              .secondaryContainer
                              .withOpacity(0.5))
                      : null,
                  borderRadius: const BorderRadius.all(Radius.circular(8.0))),
              child: Text(
                index < testLimit ? word : "✴︎",
                style: word == 'will'
                    ? TextStyle(
                        fontFamily:
                            DefaultTextStyle.of(context).style.fontFamily,
                        color: index < testLimit
                            ? Theme.of(context).colorScheme.onPrimary
                            : Theme.of(context)
                                .colorScheme
                                .onSecondaryContainer
                                .withOpacity(0.35),
                        fontSize:
                            Theme.of(context).textTheme.titleLarge?.fontSize,
                      )
                    : TextStyle(
                        fontFamily:
                            DefaultTextStyle.of(context).style.fontFamily,
                        color: index < testLimit
                            ? Theme.of(context).colorScheme.onSurfaceVariant
                            : Theme.of(context)
                                .colorScheme
                                .onBackground
                                .withOpacity(0.25),
                        fontSize:
                            Theme.of(context).textTheme.titleLarge?.fontSize,
                      ),
              )));
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: SingleChildScrollView(
        child: Center(
          child: RichText(
            text: TextSpan(children: spans),
            textAlign: TextAlign.justify,
          ),
        ),
      ),
    );
  }
}
