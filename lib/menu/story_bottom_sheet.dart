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
            final wordToLeveNr = {for (var item in snapshot.data!.$1) item.$1.toLowerCase() : item.$3};
            final allTextWords = snapshot.data!.$1.fold(
                List<String>.empty(growable: true),
                (previousValue, element) =>
                    previousValue + element.$2.split(' '));
            final limit = snapshot.data!.$2;

            List<WidgetSpan> spans = allTextWords.mapIndexed((index, word) {
              final wordWithoutPunctuation = word.replaceAll(punctuation, '');
              final text = index < limit ? word : "✴︎";
              final isWordLevel = wordToLeveNr.containsKey(wordWithoutPunctuation);
              final levelNr = wordToLeveNr[wordWithoutPunctuation] ?? -1;
              return WidgetSpan(
                  child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 2.0),
                      padding: const EdgeInsets.symmetric(horizontal: 6.0),
                      decoration: BoxDecoration(
                          border: Border.all(color: Colors.transparent),
                          color: isWordLevel
                              ? (index < limit
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context)
                                      .colorScheme
                                      .secondaryContainer
                                      .withOpacity(0.5))
                              : null,
                          borderRadius:
                              const BorderRadius.all(Radius.circular(8.0))),
                      child: GestureDetector(
                        onTap: isWordLevel ? () {
                          _log.log(Level.INFO, "Now loading level $levelNr ");
                          levelModel.loadLevel(levelNr);
                          Navigator.pop(context);
                          } : null,
                        child: Text(
                        text,
                        style: isWordLevel
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
                      ))));
            }).toList();

            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: DraggableScrollableSheet(
                maxChildSize: 0.5,
                initialChildSize: 0.5,
                expand: false,
                builder: (context, scrollController) {
                  return RawScrollbar(
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(8.0),
                      child: Center(
                          child: RichText(
                            text: TextSpan(children: spans),
                            textAlign: TextAlign.left,
                          ),
                        ),
                      ),
                    );
                }));
          } else {
            return const CircularProgressIndicator();
          }
        });
  }
}
