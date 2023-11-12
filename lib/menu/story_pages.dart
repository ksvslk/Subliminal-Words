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

  Future<List<WidgetSpan>> createWidgetSpans(
    (List<(String, String, int)>, int) data,
    BuildContext context,
    LevelModel levelModel,
  ) async {
    // Mapping words to their respective level numbers
    final Map<String, int> wordToLevelNumber = {
      for (var item in data.$1) item.$1.replaceAll(punctuation, ''): item.$3
    };

    // Flattening the list of words and pairing with their level numbers
    final List<(String, int)> allWords = data.$1.fold(
      List<(String, int)>.empty(growable: true),
      (previousValue, element) {
        return previousValue +
            element.$2.split(' ').map((word) => (word, element.$3)).toList();
      },
    );

    final int limit = data.$2;

    // Creating WidgetSpan for each word
    return allWords.asMap().entries.map((entry) {
      int index = entry.key;
      var word = entry.value.$1;
      int wordLevel = entry.value.$2;

      String wordWithoutPunctuation = word.replaceAll(punctuation, '');
      bool isWordLevel = wordToLevelNumber.containsKey(wordWithoutPunctuation);
      int levelNr = wordToLevelNumber[wordWithoutPunctuation] ?? -1;

      bool isWithinLimit = index < limit;
      bool isClickable = isWordLevel && levelNr == wordLevel;

      return _createWidgetSpan(
        context,
        word: isWithinLimit ? word : "_",
        isClickable: isClickable,
        index: index,
        limit: limit,
        onTap: () {
          if (isClickable) {
            levelModel.loadLevel(levelNr, fromLevelSelect: true);
            Navigator.of(context).pop();
          }
        },
      );
    }).toList();
  }

  WidgetSpan _createWidgetSpan(
    BuildContext context, {
    required String word,
    required bool isClickable,
    required int index,
    required int limit,
    VoidCallback? onTap,
  }) {
    TextStyle baseStyle = DefaultTextStyle.of(context).style;
    ColorScheme colorScheme = Theme.of(context).colorScheme;

    return WidgetSpan(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2.0),
        padding: const EdgeInsets.symmetric(horizontal: 6.0),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.transparent),
          color: isClickable
              ? (index < limit
                  ? colorScheme.primary
                  : colorScheme.secondaryContainer.withOpacity(0.5))
              : null,
          borderRadius: const BorderRadius.all(Radius.circular(8.0)),
        ),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Text(
            word,
            style: TextStyle(
              fontFamily: baseStyle.fontFamily,
              color: isClickable
                  ? (index < limit
                      ? colorScheme.onPrimary
                      : colorScheme.onSecondaryContainer.withOpacity(0.35))
                  : (index < limit
                      ? colorScheme.onSurfaceVariant
                      : colorScheme.onBackground.withOpacity(0.25)),
              fontSize: Theme.of(context).textTheme.titleLarge?.fontSize,
            ),
          ),
        ),
      ),
    );
  }

  Future<List<StoryCard>> combinedF(
      BuildContext context, LevelModel levelModel) async {
    var stuff = await levelModel.getAllLevelsWordAndStories();
    var results = await createWidgetSpans(stuff, context, levelModel);
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
