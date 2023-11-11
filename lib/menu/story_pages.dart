import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:operation_hermes/game/model/level_model.dart';
import 'package:operation_hermes/menu/story_card.dart';
import 'package:provider/provider.dart';

class StoryPages extends StatelessWidget {
  const StoryPages({super.key});

  static RegExp punctuation = RegExp(r"[.,!?]");

  Future<List<WidgetSpan>> fff((List<(String, String, int)>, int) data,
      BuildContext context, LevelModel levelModel) async {
    final wordToLeveNr = {
      for (var item in data!.$1) item.$1.replaceAll(punctuation, ''): item.$3
    };
    final allTextWords = data.$1.fold(List<String>.empty(growable: true),
        (previousValue, element) => previousValue + element.$2.split(' '));
    final limit = data.$2;

    return allTextWords.mapIndexed((index, word) {
      final wordWithoutPunctuation = word.replaceAll(punctuation, '');
      final text = index < limit ? word : "_";
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
                  borderRadius: const BorderRadius.all(Radius.circular(8.0))),
              child: GestureDetector(
                  onTap: isWordLevel
                      ? () {
                          levelModel.loadLevel(levelNr);
                        }
                      : null,
                  child: Text(
                    text,
                    style: isWordLevel
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
                  FilledButton(
                      onPressed: () => {Navigator.pop(context)},
                      child: const Text('Back to game'))
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
