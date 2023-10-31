import 'dart:ui';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:operation_hermes/game/model/level_model.dart';
import 'package:provider/provider.dart';

class StoryBottomSheet extends StatelessWidget {
  const StoryBottomSheet({super.key});
  static final _log = Logger('StoryBottomSheet');

  @override
  Widget build(BuildContext context) {
    final levelModel = context.watch<LevelModel>();
    final allLevels = levelModel.getAllLevelsWordAndStories();
    final RegExp punctuation = RegExp(r"[.,!?]");
    return FutureBuilder(
        future: allLevels,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            final levelWords = snapshot.data!.$1.map((e) => e.$1).toList();
            final allTextWords = snapshot.data!.$1.fold(
                List<String>.empty(growable: true),
                (previousValue, element) =>
                    previousValue + element.$2.split(' '));
            final limit = snapshot.data!.$2;

            _log.log(Level.INFO, "Building again with limit: $limit");
            allTextWords.forEach((element) {
              _log.log(Level.INFO, "Next: $element");
            });

            List<WidgetSpan> spans = allTextWords.mapIndexed((index, word) {
              return WidgetSpan(
                  child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 2.0),
                      padding: const EdgeInsets.symmetric(horizontal: 6.0),
                      decoration: BoxDecoration(
                          border: Border.all(color: Colors.transparent),
                          color: levelWords
                                  .contains(word.replaceAll(punctuation, ''))
                              ? (index < limit
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context)
                                      .colorScheme
                                      .secondaryContainer
                                      .withOpacity(0.5))
                              : null,
                          borderRadius:
                              const BorderRadius.all(Radius.circular(8.0))),
                      child: Text(
                        index < limit ? word : "✴︎",
                        style: levelWords
                                .contains(word.replaceAll(punctuation, ''))
                            ? TextStyle(
                                fontFamily: DefaultTextStyle.of(context)
                                    .style
                                    .fontFamily,
                                color: index < limit
                                    ? Theme.of(context).colorScheme.onPrimary
                                    : Theme.of(context)
                                        .colorScheme
                                        .onSecondaryContainer
                                        .withOpacity(0.35),
                                fontSize: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.fontSize,
                              )
                            : TextStyle(
                                fontFamily: DefaultTextStyle.of(context)
                                    .style
                                    .fontFamily,
                                color: index < limit
                                    ? Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant
                                    : Theme.of(context)
                                        .colorScheme
                                        .onBackground
                                        .withOpacity(0.25),
                                fontSize: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.fontSize,
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
          } else {
            return const CircularProgressIndicator();
          }
        });
  }
}
