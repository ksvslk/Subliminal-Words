import 'package:animations/animations.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

class StoryTablo extends StatefulWidget {
  const StoryTablo(
      {super.key,
      required this.previousLevelWordAndStory,
      required this.currentLevelWordAndStory});

  final (String, String) previousLevelWordAndStory;
  final (String, String) currentLevelWordAndStory;

  @override
  State<StoryTablo> createState() => _StoryTabloState();
}

class _StoryTabloState extends State<StoryTablo>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _offsetAnimation;
  late ScrollController _scrollController = ScrollController();


  List<WidgetSpan> getTextSpans(
      BuildContext context, (String, String) levelWordAndStory) {
    List<String> words = levelWordAndStory.$2.split(' ');
    return words.mapIndexed((index, word) {
      return WidgetSpan(
          child: Text('$word ',
              style: word == levelWordAndStory.$1
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
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 5),
      vsync: this,
    );
    _offsetAnimation = Tween<double>(begin: 0, end: 1).animate(_controller);
  }

  void changeText() {
    if (_controller.isCompleted) {
      _controller.reverse();
    } else {
      _controller.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    var previousStory = getTextSpans(context, widget.previousLevelWordAndStory);
    var currentStory = getTextSpans(context, widget.currentLevelWordAndStory);


    void changeText() {
      if (_scrollController.offset == 0) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(seconds: 10),
          curve: Curves.linear,
        );
      } else {
        _scrollController.animateTo(
          0,
          duration: const Duration(seconds: 10),
          curve: Curves.linear,
        );
      }
    }


  return GestureDetector(
    onTap: changeText,
    child: SizedBox(
      width: MediaQuery.of(context).size.width,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        controller: _scrollController,
        physics: const NeverScrollableScrollPhysics(), // Prevent manual scrolling
        child: Row(
          children: [
            RichText(
              maxLines: 1,
              overflow: TextOverflow.clip,
              text: TextSpan(children: previousStory),
            ),
            RichText(
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(children: currentStory),
            ),
          ],
        ),
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
