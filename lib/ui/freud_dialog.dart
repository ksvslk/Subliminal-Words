import 'package:animated_text_kit/animated_text_kit.dart';
import 'package:flutter/material.dart';
import 'package:operation_hermes/change_notifier/level_model.dart';
import 'package:provider/provider.dart';

class FreudDialog extends StatelessWidget {
  const FreudDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final levelModel = context.watch<LevelModel>();
    final currentTime = DateTime.now();
    final isChristmas = (currentTime.month == 12 && currentTime.day >= 1) ||
        (currentTime.month == 1 && currentTime.day <= 6);

    return ChangeNotifierProvider<LevelModel>.value(
      value: levelModel,
      child: Consumer<LevelModel>(builder: (context, levelModel, child) {
        var showTooltip = (false, "");

        if (levelModel.variousTooltip.isNotEmpty) {
          showTooltip = (true, levelModel.variousTooltip);
        } else if (!levelModel.levelCompleted &&
            levelModel.tooltipStart.isNotEmpty &&
            !levelModel.isInitialTooltipDismissed) {
          showTooltip = (true, levelModel.tooltipStart);
        } else if (levelModel.levelCompleted &&
            levelModel.tooltipEnd.isNotEmpty) {
          showTooltip = (true, levelModel.tooltipEnd);
        }

        return showTooltip.$1
            ? GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  if (levelModel.levelCompleted) {
                    levelModel.nextLevel();
                  } else {
                    levelModel.hideAllPossibleTooltips();
                  }
                },
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.center,
                      end: Alignment.bottomCenter,
                      colors: [
                        Theme.of(context).colorScheme.surface.withAlpha(0),
                        Theme.of(context)
                            .colorScheme
                            .surface, // The bottom color of the gradient
                      ],
                    ),
                  ),
                  alignment: Alignment.bottomCenter,
                  width: double.infinity,
                  height: double.infinity,
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                            flex: 2,
                            fit: FlexFit.tight,
                            child: Container(
                              margin: const EdgeInsets.all(8.0),
                              padding: const EdgeInsets.all(16.0),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surface,
                                border: Border.all(
                                    color:
                                        Theme.of(context).colorScheme.onSurface,
                                    width: 2.0),
                                borderRadius: BorderRadius.circular(10.0),
                              ),
                              child: SizedBox(
                                child: DefaultTextStyle(
                                  style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface,
                                      fontSize: Theme.of(context)
                                          .textTheme
                                          .bodyLarge
                                          ?.fontSize,
                                      fontFamily: DefaultTextStyle.of(context)
                                          .style
                                          .fontFamily),
                                  child: IgnorePointer(
                                    child: AnimatedTextKit(
                                      key: Key(showTooltip.$2),
                                      isRepeatingAnimation: false,
                                      displayFullTextOnTap: true,
                                      animatedTexts: [
                                        TypewriterAnimatedText(showTooltip.$2,
                                            speed: const Duration(
                                                milliseconds: 80),
                                            cursor: "🀫"),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            )),
                        Flexible(
                          flex: 1,
                          fit: FlexFit.tight,
                          child: Container(
                            margin: const EdgeInsets.all(8.0),
                            child: Image.asset(
                              isChristmas
                                  ? 'assets/other/freud200_winter.png'
                                  : 'assets/other/freud200.png',
                              fit: BoxFit.scaleDown,
                            ),
                          ),
                        ),
                      ]),
                ),
              )
            : const SizedBox.shrink();
      }),
    );
  }
}
