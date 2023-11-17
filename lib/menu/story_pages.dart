import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:operation_hermes/game/level_data.dart';
import 'package:operation_hermes/game/model/level_model.dart';
import 'package:operation_hermes/menu/story_card.dart';
import 'package:provider/provider.dart';

class StoryPages extends StatelessWidget {
  const StoryPages({super.key});

  static RegExp punctuation = RegExp(r"[.,!?]");
  static final _log = Logger('StoryPages');

  List<WidgetSpan> createWidgetSpans(
    (List<LevelData>,int) levelsAndContinueLevelNr,
    BuildContext context,
    LevelModel levelModel,
  ) {
    final list =
        levelsAndContinueLevelNr.$1.fold(List<WidgetSpan>.empty(growable: true), (previousLevel, currentLevel) {
      return previousLevel +
          currentLevel.story.split(' ').fold(List<WidgetSpan>.empty(growable: true), (previousWidgets, currentWord) {
            previousWidgets.add(
              _createWidgetSpan(
              context,
              word: currentLevel.word,
              storyWord: currentWord,
              isClickable: currentLevel.unlocked,
              levelNr: currentLevel.nr,
              continueLevelNr: levelsAndContinueLevelNr.$2,
              onTap: () {
                if (currentLevel.unlocked || currentLevel.nr == levelsAndContinueLevelNr.$2) {
                  levelModel.loadLevel(currentLevel.nr, fromLevelSelect: true);
                  Navigator.of(context).pop();
                }
              },
            )
            );
            return previousWidgets;
          }).toList();
    });
    return list;
  }

  Color? getColorForBox(ColorScheme colorScheme, bool isMainWord, bool isLevelUnlocked, bool continueLevel)
  {
    if (isLevelUnlocked && !isMainWord)
    {
      return null;
    }
    else if (isLevelUnlocked && isMainWord)
    {
      return colorScheme.primary;
    }
    else if (!isLevelUnlocked && isMainWord && !continueLevel)
    {
      return colorScheme.secondaryContainer;
    }
      else if (!isLevelUnlocked && isMainWord && continueLevel)
    { 
      return colorScheme.primaryContainer;
    }
    else if (!isLevelUnlocked && !isMainWord)
    {
      return null;
    }
    else {
      return colorScheme.error;
    }
  }

  Color getColorForText(ColorScheme colorScheme, bool isMainWord, bool isLevelUnlocked, bool continueLevel)
  {
     if (isLevelUnlocked && !isMainWord)
    {
      return colorScheme.onBackground;
    }
    else if (isLevelUnlocked && isMainWord)
    {
      return colorScheme.onPrimary;
    }
    else if (!isLevelUnlocked && isMainWord && !continueLevel)
    {
      return colorScheme.onSecondaryContainer;
    }
    else if (!isLevelUnlocked && isMainWord && continueLevel)
    {
      return colorScheme.onPrimaryContainer;
    }
    else if (!isLevelUnlocked && !isMainWord)
    {
      return colorScheme.onSurfaceVariant;
    }
    else {
      return colorScheme.onError;
    }
  }

  String getText(bool isMainWord, bool isLevelUnlocked, String word, bool continueLevelNr)
  {
    if (isLevelUnlocked && !isMainWord)
    {
      return word;
    }
    else if (isLevelUnlocked && isMainWord)
    {
      return word;
    }
    else if (!isLevelUnlocked && isMainWord && !continueLevelNr)
    {
      return "🔒";
    }
    else if (!isLevelUnlocked && isMainWord && continueLevelNr)
    {
      return "🔅";
    }
    else if (!isLevelUnlocked && !isMainWord)
    {
      return "_";
    }
    else {
      return "[ERROR]";
    }
  }

  WidgetSpan _createWidgetSpan(
    BuildContext context, {
    required String word,
    required String storyWord,
    required bool isClickable,
    required int levelNr,
    required int continueLevelNr,
    VoidCallback? onTap,
  }) {
    TextStyle baseStyle = DefaultTextStyle.of(context).style;
    ColorScheme colorScheme = Theme.of(context).colorScheme;

    final comparisonMainWord = word.replaceAll(punctuation, '').toLowerCase();
    final comparisonStoryWord = storyWord.replaceAll(punctuation, '').toLowerCase();
    final isMainWord = comparisonMainWord == comparisonStoryWord;
    final continueLevel = levelNr == continueLevelNr;

    return WidgetSpan(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2.0),
        padding: const EdgeInsets.symmetric(horizontal: 6.0),
        decoration: BoxDecoration(
            border: Border.all(color: Colors.transparent),
            color: getColorForBox(colorScheme, isMainWord, isClickable, continueLevel),
            borderRadius: const BorderRadius.all(Radius.circular(8.0))),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: (isMainWord && isClickable) || (isMainWord && continueLevel) ? onTap : null,
          child: Text(
            getText(isMainWord, isClickable, storyWord, continueLevel),
             style: TextStyle(
              fontFamily: baseStyle.fontFamily,
              color: getColorForText(colorScheme, isMainWord, isClickable, continueLevel),
              fontSize: Theme.of(context).textTheme.titleLarge?.fontSize,
            ),
          ),
        ),
      ),
    );
  }

  List<StoryCard> combinedF(
      BuildContext context, (List<LevelData>, int) levels, LevelModel levelModel) {
    var results = createWidgetSpans(levels, context, levelModel);
    return results.slices(50).map((e) => StoryCard(text: e)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final levelModel = context.watch<LevelModel>();
    final PageController controller = PageController(
        initialPage: levelModel.currentStoryCardPageNr.value - 1);
    return FutureBuilder(
      future: levelModel.getAllLevelsWordAndStories(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          final storyCards = combinedF(context, snapshot.data!, levelModel);
          final totalPages = storyCards.length;
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
                      children: storyCards,
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
