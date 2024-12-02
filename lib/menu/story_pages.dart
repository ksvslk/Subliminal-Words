import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:operation_hermes/game/level_data.dart';
import 'package:operation_hermes/game/model/level_model.dart';
import 'package:operation_hermes/menu/story_card.dart';
import 'package:provider/provider.dart';

class StoryPages extends StatefulWidget {
  const StoryPages({super.key});

  @override
  StoryPagesState createState() => StoryPagesState();
}

class StoryPagesState extends State<StoryPages> {
  static final _log = Logger('StoryPages');

  Future<List<WidgetSpan>> createWidgetSpans(
    (List<LevelData>, int) levelsAndContinueLevelNr,
    BuildContext context,
    LevelModel levelModel,
  ) async {
    final list = levelsAndContinueLevelNr.$1.fold(
        List<WidgetSpan>.empty(growable: true), (previousLevel, currentLevel) {
      return previousLevel +
          currentLevel.story
              .split(' ')
              .fold(List<WidgetSpan>.empty(growable: true),
                  (previousWidgets, currentWord) {
            previousWidgets.add(_createWidgetSpan(
              context,
              word: currentLevel.word,
              storyWord: currentWord,
              isClickable: currentLevel.unlocked,
              levelNr: currentLevel.nr,
              continueLevelNr: levelsAndContinueLevelNr.$2,
              onTap: () {
                if (currentLevel.unlocked ||
                    currentLevel.nr == levelsAndContinueLevelNr.$2) {
                  levelModel.loadLevel(currentLevel.nr, fromLevelSelect: true);
                  Navigator.of(context).pop();
                }
              },
            ));
            return previousWidgets;
          }).toList();
    });
    return list;
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

    final comparisonMainWord =
        word.replaceAll(RegExp(r"[.,!?]"), '').toLowerCase();
    final comparisonStoryWord =
        storyWord.replaceAll(RegExp(r"[.,!?]"), '').toLowerCase();
    final isMainWord = comparisonMainWord == comparisonStoryWord;
    final continueLevel = levelNr == continueLevelNr;

    return WidgetSpan(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2.0),
        padding: const EdgeInsets.symmetric(horizontal: 6.0),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.transparent),
          color: _getColorForBox(
              colorScheme, isMainWord, isClickable, continueLevel),
          borderRadius: const BorderRadius.all(Radius.circular(8.0)),
        ),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: (isMainWord && isClickable) || (isMainWord && continueLevel)
              ? onTap
              : null,
          child: Text(
            _getText(isMainWord, isClickable, storyWord, continueLevel),
            style: TextStyle(
              fontFamily: baseStyle.fontFamily,
              color: _getColorForText(
                  colorScheme, isMainWord, isClickable, continueLevel),
              fontSize: Theme.of(context).textTheme.titleLarge?.fontSize,
            ),
          ),
        ),
      ),
    );
  }

  Color? _getColorForBox(ColorScheme colorScheme, bool isMainWord,
      bool isLevelUnlocked, bool continueLevel) {
    if (isLevelUnlocked && !isMainWord) {
      return null;
    } else if (isLevelUnlocked && isMainWord) {
      return colorScheme.primary;
    } else if (!isLevelUnlocked && isMainWord && !continueLevel) {
      return colorScheme.secondaryContainer;
    } else if (!isLevelUnlocked && isMainWord && continueLevel) {
      return colorScheme.primaryContainer;
    } else if (!isLevelUnlocked && !isMainWord) {
      return null;
    } else {
      return colorScheme.error;
    }
  }

  Color _getColorForText(ColorScheme colorScheme, bool isMainWord,
      bool isLevelUnlocked, bool continueLevel) {
    if (isLevelUnlocked && !isMainWord) {
      return colorScheme.onBackground;
    } else if (isLevelUnlocked && isMainWord) {
      return colorScheme.onPrimary;
    } else if (!isLevelUnlocked && isMainWord && !continueLevel) {
      return colorScheme.onSecondaryContainer;
    } else if (!isLevelUnlocked && isMainWord && continueLevel) {
      return colorScheme.onPrimaryContainer;
    } else if (!isLevelUnlocked && !isMainWord) {
      return colorScheme.onSurfaceVariant;
    } else {
      return colorScheme.onError;
    }
  }

  String _getText(
      bool isMainWord, bool isLevelUnlocked, String word, bool continueLevel) {
    if (isLevelUnlocked && !isMainWord) {
      return word;
    } else if (isLevelUnlocked && isMainWord) {
      return word;
    } else if (!isLevelUnlocked && isMainWord && !continueLevel) {
      return "🔒";
    } else if (!isLevelUnlocked && isMainWord && continueLevel) {
      return "🔅";
    } else if (!isLevelUnlocked && !isMainWord) {
      return "_";
    } else {
      return "[ERROR]";
    }
  }

  Future<List<StoryCard>> _getStoryCards(
    BuildContext context,
    LevelModel levelModel,
    (List<LevelData>, int) levels,
  ) async {
    var widgetSpans = await createWidgetSpans(levels, context, levelModel);
    return widgetSpans
        .slices(50)
        .map((slice) => StoryCard(text: slice))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final levelModel = context.watch<LevelModel>();
    final PageController controller = PageController(initialPage: 1);

    final loadingPageCard = PageView(
        clipBehavior: Clip.hardEdge,
        scrollDirection: Axis.vertical,
        controller: controller,
        children: const [
          Center(
            child: Card(
              child: Center(
                child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator()),
              ),
            ),
          )
        ]);

    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              OutlinedButton(
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.resolveWith<Color>(
                    (Set<WidgetState> states) {
                      if (states.contains(WidgetState.selected)) {
                        return Theme.of(context).colorScheme.primary;
                      }
                      return Theme.of(context).colorScheme.secondaryContainer;
                    },
                  ),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text('Back to game'),
              ),
              SegmentedButton<int>(
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.resolveWith<Color>(
                    (Set<WidgetState> states) {
                      if (states.contains(WidgetState.selected)) {
                        return Theme.of(context).colorScheme.primary;
                      }
                      return Theme.of(context).colorScheme.secondaryContainer;
                    },
                  ),
                  foregroundColor: WidgetStateProperty.resolveWith<Color>(
                    (Set<WidgetState> states) {
                      if (states.contains(WidgetState.selected)) {
                        return Theme.of(context).colorScheme.onPrimary;
                      }
                      return Theme.of(context).colorScheme.onSecondaryContainer;
                    },
                  ),
                ),
                showSelectedIcon: false, // This removes the tick icon
                segments: const <ButtonSegment<int>>[
                  ButtonSegment<int>(
                    value: 1,
                    label: Text('Chapter 1'),
                  ),
                  ButtonSegment<int>(
                    value: 2,
                    label: Text('Chapter 2'),
                  ),
                  ButtonSegment<int>(
                    value: 3,
                    label: Text('Quest'),
                  ),
                ],
                selected: {levelModel.currentStoryCardPack},
                onSelectionChanged: (chapter) async {
                  levelModel.changeStoryPackNr(chapter.first);
                  controller.jumpToPage(0);
                },
              ),
              Expanded(
                child: FutureBuilder(
                  future: levelModel.getCurrentStoryLevelsAndContinueLevel(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return Stack(
                        children: [
                          loadingPageCard,
                        ],
                      );
                    }

                    return FutureBuilder<List<StoryCard>>(
                      future:
                          _getStoryCards(context, levelModel, snapshot.data!),
                      builder: (context, storySnapshot) {
                        if (!storySnapshot.hasData) {
                          return Stack(
                            children: [
                              loadingPageCard,
                            ],
                          );
                        }

                        final storyCards = storySnapshot.data!;

                        return Stack(
                          children: [
                            PageView(
                              clipBehavior: Clip.hardEdge,
                              scrollDirection: Axis.vertical,
                              controller: controller,
                              children: levelModel.networkRequestActive
                                  ? [
                                      loadingPageCard,
                                    ]
                                  : storyCards,
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
