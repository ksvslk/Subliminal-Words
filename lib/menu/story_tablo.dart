import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:operation_hermes/game/model/level_model.dart';
import 'package:operation_hermes/game/model/story_model.dart';
import 'package:provider/provider.dart';

class StoryTablo extends StatefulWidget {
  const StoryTablo({super.key});

  @override
  State<StoryTablo> createState() => _StoryTabloState();
}

class _StoryTabloState extends State<StoryTablo>
    with SingleTickerProviderStateMixin {
  late ScrollController _scrollController;
  final RegExp punctuation = RegExp(r"[.,!?]");

  static final _log = Logger('StoryTablo');

  RichText getRichText(
      BuildContext context, (String, String) levelWordAndStory) {
    final List<String> words = levelWordAndStory.$2.split(' ');
    final inlineSpans = words.mapIndexed((index, word) {
      return WidgetSpan(
          child: Text('$word ',
              style: word.replaceAll(punctuation, "") ==
                      levelWordAndStory.$1.toLowerCase()
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

  List<RichText> getStories(List<(String, String)> stories) {
    for (var element in stories) {
      _log.log(Level.INFO, "rich text: $element");
    }
    return List.of(stories.map((e) => getRichText(context, e)));
  }

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  void _scrollToEnd() {
    _scrollController.animateTo(_scrollController.position.maxScrollExtent,
        duration: const Duration(seconds: 5), curve: Curves.linear);
  }

  void _scrollToEndWithoutAnimation() {
    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
  }

  @override
  Widget build(BuildContext context) {
    final levelModel = context.read<LevelModel>();
    return ChangeNotifierProvider<StoryModel>.value(
        value: levelModel.storyModel,
        child: Consumer<StoryModel>(builder: (context, model, child) {
          if (model.storyToCreate.length > 1) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
          } else {
            WidgetsBinding.instance
                .addPostFrameCallback((_) => _scrollToEndWithoutAnimation());
          }

          _log.info(
              "Rebuilding in consumer: Count of story row children: ${model.storyToCreate.length}");
          return SizedBox(
            width: MediaQuery.of(context).size.width,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              controller: _scrollController,
              clipBehavior: Clip.hardEdge,
              physics:
                  const NeverScrollableScrollPhysics(), // Prevent manual scrolling
              child: Row(children: getStories(model.storyToCreate)),
            ),
          );
        }));
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}
