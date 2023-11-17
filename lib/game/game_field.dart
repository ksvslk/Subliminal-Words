import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:operation_hermes/ads/ads_controller.dart';
import 'package:operation_hermes/audio/audio_controller.dart';
import 'package:operation_hermes/audio/sounds.dart';
import 'package:operation_hermes/game/model/field_model.dart';
import 'package:operation_hermes/game/letter_box.dart';
import 'package:operation_hermes/game/letter_box_data.dart';
import 'package:operation_hermes/game/letter_box_state.dart';
import 'package:operation_hermes/game/model/level_model.dart';
import 'package:operation_hermes/games_services/games_services.dart';
import 'package:operation_hermes/in_app_purchase/in_app_purchase_controller.dart';
import 'package:provider/provider.dart';

class GameField extends StatelessWidget {
  const GameField({super.key});
  static final _log = Logger('GameField');

  @override
  Widget build(BuildContext context) {
    final audioController = context.read<AudioController>();
    final levelModel = context.watch<LevelModel>();
    final gamesServices = context.read<GamesServicesController>();
    final purchaseController = context.read<InAppPurchaseController>();
    final adsController = context.read<AdsController>();

    _log.log(Level.INFO, "Rebuilding whole GameField.");

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (levelModel.levelCompleted && purchaseController.isNoAdsPurchased() &&
          levelModel.levelNr >= 20 &&
          levelModel.levelNr % 5 == 0) {
        adsController.loadInterstitialAd(null);
      }
    });

    return Column(
      children: [
        const Flexible(child: FractionallySizedBox(heightFactor: 0.5)),
        Flexible(
          flex: 10,
          child: ChangeNotifierProvider<FieldModel>.value(
            value: levelModel.fieldModel,
            child: Consumer<FieldModel>(builder: (context, fieldModel, child) {
              _log.log(Level.INFO, "Rebuilding GameField SOLUTION field.");
              return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final (i, _) in fieldModel.solution.indexed)
                      Flexible(
                        child: ChangeNotifierProvider.value(
                          value: fieldModel.solution[i],
                          child: Consumer<LetterBoxData>(
                            builder: (context, data, child) {
                              _log.log(
                                  Level.INFO, "Rebuilding Letter in GameField");
                              return GestureDetector(
                                onTap: () {
                                  if (data.state ==
                                          LetterBoxState.solutionPick &&
                                      !levelModel.levelCompleted) {
                                    audioController.playSfx(SfxType.freeLetter);
                                    fieldModel.removeLetter(i, data);
                                  }
                                },
                                child: AspectRatio(
                                  aspectRatio: 1,
                                  child: LetterBox(
                                    key: ValueKey('solution-$i'),
                                    data: data,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                  ]);
            }),
          ),
        ),
        const Flexible(child: FractionallySizedBox(heightFactor: 0.5)),
        ...List.generate(2, (rowIndex) {
          return Flexible(
            flex: 10,
            child: ChangeNotifierProvider<FieldModel>.value(
              value: levelModel.fieldModel,
              child:
                  Consumer<FieldModel>(builder: (context, fieldModel, child) {
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(7, (columnIndex) {
                    int index = rowIndex * 7 + columnIndex;
                    return Flexible(
                      child: ChangeNotifierProvider.value(
                          value: fieldModel.field[index],
                          child: Consumer<LetterBoxData>(
                              builder: (context, data, child) {
                            return GestureDetector(
                              onTap: () {
                                if (!levelModel.levelCompleted &&
                                    data.state == LetterBoxState.fieldPick &&
                                    !fieldModel.isLastLetter()) {
                                  HapticFeedback.selectionClick();
                                  audioController.playSfx(SfxType.pickLetter);
                                  fieldModel.putLetter(index, data);
                                  var result = levelModel.checkForWin();
                                  if (result) {
                                    HapticFeedback.mediumImpact();
                                    audioController.playSfx(SfxType.win);
                                    gamesServices.unlockAchievementForLevel(
                                        levelModel.levelNr);
                                  }
                                }
                              },
                              child: AspectRatio(
                                aspectRatio: 1,
                                child: LetterBox(data: data),
                              ),
                            );
                          })),
                    );
                  }),
                );
              }),
            ),
          );
        }),
      ],
    );
  }
}
