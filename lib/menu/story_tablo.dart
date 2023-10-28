import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:operation_hermes/game/model/level_model.dart';
import 'package:provider/provider.dart';

class StoryTablo extends StatefulWidget {
  const StoryTablo({super.key});

  @override
  State<StoryTablo> createState() => _StoryTabloState();
}

class _StoryTabloState extends State<StoryTablo>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late ScrollController _scrollController;
  final RegExp punctuation = RegExp(r"[.,!?]");

  final List<Widget> storyRowChildren = [];
  static final _log = Logger('StoryTablo');

  RichText getRichText(
      BuildContext context, (String, String) levelWordAndStory) {
    final List<String> words = levelWordAndStory.$2.split(' ');
    final inlineSpans = words.mapIndexed((index, word) {
      return WidgetSpan(
          child: Text('$word ',
              style: word.replaceAll(punctuation, "") == levelWordAndStory.$1.toLowerCase()
                  ? TextStyle(
                      fontFamily: DefaultTextStyle.of(context).style.fontFamily,
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: Theme.of(context).textTheme.bodyLarge?.fontSize,
                    )
                  : TextStyle(
                      fontFamily: DefaultTextStyle.of(context).style.fontFamily,
                      color: Theme.of(context).colorScheme.onBackground,
                      fontSize: Theme.of(context).textTheme.bodyLarge?.fontSize,
                    )));
    }).toList();
    return RichText(
      maxLines: 1,
      overflow: TextOverflow.clip,
      text: TextSpan(children: inlineSpans),
    );
  }

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _controller = AnimationController(
      duration: const Duration(seconds: 5),
      vsync: this,
    );
  }

  void _scrollToEnd() {
    _scrollController.animateTo(_scrollController.position.maxScrollExtent,
        duration: const Duration(seconds: 5), curve: Curves.linear);
  }

  @override
  Widget build(BuildContext context) {
    final levelModel = context.watch<LevelModel>();

    void addCompletedLevelText() {
      final currentLevelStory =
          getRichText(context, (levelModel.currentWordAndStory));
      setState(() {
        storyRowChildren.add(currentLevelStory);
      });
      _log.info("Count of story row children: ${storyRowChildren.length}");
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(seconds: 10),
        curve: Curves.linear,
      ).whenComplete(() {
        if (storyRowChildren.length == 3) storyRowChildren.removeAt(0);
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());

    // Game just started
    if (storyRowChildren.isEmpty) {
      final previousStory =
          getRichText(context, levelModel.previousWordAndStory);
      storyRowChildren.add(previousStory);
    // When level is completed and previous already in place
    } else if (storyRowChildren.isNotEmpty && levelModel.levelCompleted) {
      addCompletedLevelText();
    }
    _log.info(
        "Rebuilding in consumer: Count of story row children: ${storyRowChildren.length}");

    return SizedBox(
      width: MediaQuery.of(context).size.width,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        controller: _scrollController,
        clipBehavior: Clip.hardEdge,
        physics:
            const NeverScrollableScrollPhysics(), // Prevent manual scrolling
        child: Row(
          children: storyRowChildren,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}
