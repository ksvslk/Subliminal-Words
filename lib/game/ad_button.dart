import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:operation_hermes/ads/ads_controller.dart';
import 'package:operation_hermes/audio/audio_controller.dart';
import 'package:operation_hermes/audio/sounds.dart';
import 'package:operation_hermes/game/ad_button_name.dart';
import 'package:operation_hermes/game/model/hint_model.dart';
import 'package:operation_hermes/game/model/level_model.dart';
import 'package:provider/provider.dart';

class AdButton extends StatelessWidget {
  const AdButton({super.key, required this.adButtonName});

  final AdButtonName adButtonName;

  String getName() {
    switch (adButtonName) {
      case AdButtonName.remove3:
        return "Remove 3";
      case AdButtonName.zoom:
        return "Zoom";
      case AdButtonName.highlight:
        return "Highlight";
    }
  }

  Function()? getAction(HintModel hintModel, LevelModel levelModel,
      AudioController audioController, AdsController adsController) {
    switch (adButtonName) {
      case AdButtonName.remove3:
        if (!hintModel.remove3Purchased && hintModel.lettersCanBeRemoved) {
          return () {
            adsController.takePreloadedAd()?.showRewardedAd(() {
              audioController.playSfx(SfxType.wrong);
              levelModel.remove3ArbitaryLetters();
            });
          };
        }
        return null;
      case AdButtonName.zoom:
        if (!hintModel.zoomPurchased) {
          return () {
            adsController.takePreloadedAd()?.showRewardedAd(() {
              audioController.playSfx(SfxType.rewardGiven);
              hintModel.activateZoom();
            });
          };
        }
        return null;
      case AdButtonName.highlight:
        if (!hintModel.highlightPurchased) {
          return () {
            adsController.takePreloadedAd()?.showRewardedAd(() {
              audioController.playSfx(SfxType.rewardGiven);
              levelModel.highlightLetter();
            });
          };
        }
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final levelModel = context.read<LevelModel>();
    final audioController = context.read<AudioController>();
    final adsController = context.read<AdsController>();

    return Consumer<HintModel>(builder: (context, hintModel, child) {
      return Padding(
        padding: const EdgeInsets.all(4.0),
        child: FilledButton(
          onPressed:
              getAction(hintModel, levelModel, audioController, adsController),
          child: Text(getName()),
        ),
      );
    });
  }
}
