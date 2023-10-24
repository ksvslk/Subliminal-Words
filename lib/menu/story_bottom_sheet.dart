import 'dart:ui';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

class StoryBottomSheet extends StatelessWidget {
  const StoryBottomSheet({super.key});

  @override
  Widget build(BuildContext context) {
    String text =
        'The value provided in fontFamily will act as the preferred/first font family that will be searched for, followed in order by the font families in fontFamilyFallback. If all font families are exhausted and no match was found, the default platform font family will be used instead. Unlike TextStyle.fontFamilyFallback, the font does not need to contain the desired glyphs to match.The value provided in fontFamily will act as the preferred/first font family that will be searched for, followed in order by the font families in fontFamilyFallback. If all font families are exhausted and no match was found, the default platform font family will be used instead. Unlike TextStyle.fontFamilyFallback, the font does not need to contain the desired glyphs to match.';
    List<String> words = text.split(' ');
    List<WidgetSpan> spans = words.mapIndexed((index, word) {
      return WidgetSpan(
          child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6.0),
              decoration: BoxDecoration(
                  border: Border.all(color: Colors.transparent),
                  color: word == 'will'
                      ? (index < 20
                          ? Theme.of(context).colorScheme.tertiary
                          : Theme.of(context)
                              .colorScheme
                              .secondaryContainer
                              .withOpacity(0.5))
                      : null,
                  borderRadius: const BorderRadius.all(Radius.circular(8.0))),
              child: Text(
                index < 20 ? word : "➹",
                style: word == 'will'
                    ? TextStyle(
                        fontFamily:
                            DefaultTextStyle.of(context).style.fontFamily,
                        color: index < 20
                            ? Theme.of(context).colorScheme.onTertiary
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
                        color: index < 20
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
