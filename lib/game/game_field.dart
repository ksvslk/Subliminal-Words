import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:operation_hermes/audio/audio_controller.dart';
import 'package:operation_hermes/audio/sounds.dart';
import 'package:operation_hermes/game/model/field_model.dart';
import 'package:operation_hermes/game/letter_box.dart';
import 'package:operation_hermes/game/letter_box_data.dart';
import 'package:operation_hermes/game/letter_box_state.dart';
import 'package:operation_hermes/game/model/level_model.dart';
import 'package:operation_hermes/game/model/picture_model.dart';
import 'package:operation_hermes/game/ad_button.dart';
import 'package:operation_hermes/game/puzzle.dart';
import 'package:operation_hermes/menu/in_app_purchase_menu.dart';
import 'package:operation_hermes/menu/story_bottom_sheet.dart';
import 'package:operation_hermes/menu/story_tablo.dart';
import 'package:operation_hermes/settings/settings_controller.dart';
import 'package:provider/provider.dart';
import '../C.dart' as C;

class GameField extends StatelessWidget {
  const GameField({super.key});
  static final _log = Logger('GameField');

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final audioController = context.read<AudioController>();
    final levelModel = context.read<LevelModel>();

    _log.log(Level.INFO, "Rebuilding whole GameField.");

    void showMenu(BuildContext context) {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return const InAppPurchaseMenuDialog();
        },
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Flexible(
                        flex: 1,
                        child: IconButton(
                            onPressed: () {},
                            icon: const Icon(Icons.settings))),
                    Flexible(
                        flex: 1,
                        child: IconButton(
                            onPressed: () {
                              showMenu(context);
                            },
                            icon:
                                const Icon(Icons.add_shopping_cart_outlined))),
                    Flexible(
                      flex: 6,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(
                              10), // Adjust the radius as needed
                          border:
                              Border.all(color: Theme.of(context).colorScheme.outline), // Border style
                        ),
                        padding: const EdgeInsets.all(
                            8), // Padding inside the container
                        child: /* GestureDetector(
                        onTap: () {
                          showModalBottomSheet<void>(
                              context: context,
                              builder: (BuildContext context) {
                                return const StoryBottomSheet();
                              });
                        },
                        child: */
                            const StoryTablo(
                          previousLevelWordAndStory: (
                            "sun",
                            "Amid the vast city's hustle, a sun begins to rise on Max."
                          ),
                          currentLevelWordAndStory: (
                            "old",
                            "Recalling old tales of valor, he aspires to be more than his past."
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                ChangeNotifierProvider<PictureModel>.value(
                    value: levelModel.pictureModel, child: const Puzzle()),
                ChangeNotifierProvider<FieldModel>.value(
                  value: levelModel.fieldModel,
                  child: Consumer<FieldModel>(
                      builder: (context, fieldModel, child) {
                    _log.log(
                        Level.INFO, "Rebuilding GameField SOLUTION field.");
                    return Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (final (i, _) in fieldModel.solution.indexed)
                            Flexible(
                              child: ChangeNotifierProvider.value(
                                value: fieldModel.solution[i],
                                child: Consumer<LetterBoxData>(
                                  builder: (context, data, child) {
                                    _log.log(Level.INFO,
                                        "Rebuilding Letter in GameField");
                                    return GestureDetector(
                                      onTap: () {
                                        if (data.state ==
                                                LetterBoxState.solutionPick &&
                                            !levelModel.levelCompleted) {
                                          audioController
                                              .playSfx(SfxType.freeLetter);
                                          fieldModel.removeLetter(i, data);
                                        }
                                      },
                                      child: LetterBox(
                                        key: ValueKey('solution-$i'),
                                        data: data,
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                        ]);
                  }),
                ),
                const Divider(),
                ChangeNotifierProvider<FieldModel>.value(
                  value: levelModel.fieldModel,
                  child: Consumer<FieldModel>(
                      builder: (context, fieldModel, child) {
                    _log.log(Level.INFO, "Rebuilding GameField LETTERS field.");
                    return Column(
                      children: List.generate(
                        2,
                        (rowIndex) => Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(
                            7,
                            (columnIndex) {
                              var index = rowIndex * 7 + columnIndex;
                              return Flexible(
                                child: ChangeNotifierProvider.value(
                                  value: fieldModel.field[index],
                                  child: Consumer<LetterBoxData>(
                                    builder: (context, data, child) {
                                      _log.log(Level.INFO,
                                          "Rebuilding Letter in GameField");
                                      return GestureDetector(
                                        onTap: () {
                                          if (!levelModel.levelCompleted &&
                                              data.state ==
                                                  LetterBoxState.fieldPick &&
                                              !fieldModel.isLastLetter()) {
                                            HapticFeedback.selectionClick();
                                            audioController
                                                .playSfx(SfxType.pickLetter);
                                            fieldModel.putLetter(index, data);
                                            var result =
                                                levelModel.checkForWin();
                                            if (result) {
                                              HapticFeedback.mediumImpact();
                                              audioController
                                                  .playSfx(SfxType.win);
                                            }
                                          }
                                        },
                                        child: LetterBox(
                                          key: ValueKey('field-$index'),
                                          data: data,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  }),
                ),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Expanded(
                      flex: 1,
                      child: AdButton(productId: C.REMOVE_3),
                    ),
                    Expanded(
                      flex: 1,
                      child: AdButton(productId: C.MANIPULATE),
                    ),
                    Expanded(
                      flex: 1,
                      child: AdButton(productId: C.HIGHLIGHT),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
