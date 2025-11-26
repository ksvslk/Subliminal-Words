
import 'package:flutter/material.dart';
import 'package:operation_hermes/config/C.dart';
import 'package:operation_hermes/change_notifier/level_model.dart';
import 'package:operation_hermes/controller/shimmer_placeholders.dart';
import 'package:operation_hermes/ui/ad_button.dart';
import 'package:provider/provider.dart';

class HintBar extends StatelessWidget {
  const HintBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<LevelModel>(builder: (context, levelModel, child) {
      if (levelModel.networkRequestActive) {
        return const ActionButtonsPlaceholder();
      }
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Flexible(
            flex: 1,
            child: AdButton(
              entitlementId: C.entitlementRemove3Id,
              onReward: levelModel.remove3Action,
            ),
          ),
          Flexible(
            flex: 1,
            child: AdButton(
              entitlementId: C.entitlementManipulateId,
              onReward: levelModel.manipulationAction,
            ),
          ),
          Flexible(
            flex: 1,
            child: levelModel.currentLevel?.hintType == 'fact'
                ? AdButton(
                    entitlementId: C.entitlementHighlightId,
                    overrideTitle: 'Fact',
                    onReward: levelModel.showFactAction)
                : AdButton(
                    entitlementId: C.entitlementHighlightId,
                    overrideTitle: 'Highlight',
                    onReward: levelModel.highlightAction),
          ),
        ],
      );
    });
  }
}
