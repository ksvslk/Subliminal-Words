import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:operation_hermes/game/model/level_model.dart';
import 'package:operation_hermes/menu/story_card.dart';
import 'package:provider/provider.dart';

class StoryPages extends StatelessWidget {
  const StoryPages({super.key});

  static RegExp punctuation = RegExp(r"[.,!?]");
  static final _log = Logger('StoryPages');

  Future<List<WidgetSpan>> fff((List<(String, String, int)>, int) data,
      BuildContext context, LevelModel levelModel) async {
    final wordToLeveNr = {
      for (var item in data.$1) item.$1.replaceAll(punctuation, ''): item.$3
    };
    final allTextWords = data.$1.fold(List<(String, int)>.empty(growable: true),
        (previousValue, element) {
          _log.log(Level.INFO, "Element: ${element.$3}");
          return previousValue + element.$2.split(' ').map((e) => (e, element.$3)).toList();
        } );
    final limit = data.$2;

    return allTextWords.mapIndexed((index, word) {
      final wordWithoutPunctuation = word.$1.replaceAll(punctuation, '');
      final text = index < limit ? word.$1 : "_";
      final isWordLevel = wordToLeveNr.containsKey(wordWithoutPunctuation);

      final levelNr = wordToLeveNr[wordWithoutPunctuation] ?? -1;
      if (isWordLevel) {
        _log.log(Level.INFO, "Index in map: $index");
        _log.log(Level.INFO,
            "Is word level. Level nr: $levelNr, word: $wordWithoutPunctuation");
      }
    var isReallyWordLevel = isWordLevel && levelNr == word.$2;

      return WidgetSpan(
          child: Container(
              margin: const EdgeInsets.symmetric(vertical: 2.0),
              padding: const EdgeInsets.symmetric(horizontal: 6.0),
              decoration: BoxDecoration(
                  border: Border.all(color: Colors.transparent),
                  color: isReallyWordLevel
                      ? (index < limit
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context)
                              .colorScheme
                              .secondaryContainer
                              .withOpacity(0.5))
                      : null,
                  borderRadius: const BorderRadius.all(Radius.circular(8.0))),
              child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: isReallyWordLevel
                      ? () {
                          levelModel.loadLevel(levelNr);
                          Navigator.of(context).pop();
                        }
                      : null,
                  child: Text(
                    text,
                    style: isReallyWordLevel
                        ? TextStyle(
                            fontFamily:
                                DefaultTextStyle.of(context).style.fontFamily,
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
                            fontFamily:
                                DefaultTextStyle.of(context).style.fontFamily,
                            color: index < limit
                                ? Theme.of(context).colorScheme.onSurfaceVariant
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
  }

  Future<List<StoryCard>> combinedF(
      BuildContext context, LevelModel levelModel) async {
    var stuff = await levelModel.getAllLevelsWordAndStories();
    var results = await fff(stuff, context, levelModel);
    return results.slices(50).map((e) => StoryCard(text: e)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final levelModel = context.watch<LevelModel>();
    final PageController controller = PageController(
        initialPage: levelModel.currentStoryCardPageNr.value - 1);
    return FutureBuilder(
      future: combinedF(context, levelModel),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          final totalPages = snapshot.data!.length;
          return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: FilledButton(
                        onPressed: () => {Navigator.pop(context)},
                        child: const Text('Back to game')),
                  ),
                  Expanded(
                    flex: 20,
                    child: PageView(
                      clipBehavior: Clip.hardEdge,
                      scrollDirection: Axis.vertical,
                      controller: controller,
                      children: snapshot.data!,
                      onPageChanged: (value) {
                        levelModel.currentStoryCardPageNr.value = value + 1;
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: ValueListenableBuilder<int>(
                        builder:
                            (BuildContext context, int value, Widget? child) {
                          return LinearProgressIndicator(
                              minHeight: 8.0,
                              value: value / totalPages,
                              borderRadius: BorderRadius.circular(8));
                        },
                        valueListenable: levelModel.currentStoryCardPageNr),
                  ),
                ],
              ));
        } else {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }
      },
    );
  }
}
