
import 'dart:io';

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

      final remove3ProductId = Platform.isAndroid ? C.REMOVE_3 : C.REMOVE_3_IOS;
      final manipulateProductId =
          Platform.isAndroid ? C.MANIPULATE : C.MANIPULATE_IOS;
      final highlightProductId =
          Platform.isAndroid ? C.HIGHLIGHT : C.HIGHLIGHT_IOS;

      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Flexible(
            flex: 1,
            child: AdButton(
              productId: remove3ProductId,
              onReward: levelModel.remove3Action,
            ),
          ),
          Flexible(
            flex: 1,
            child: AdButton(
              productId: manipulateProductId,
              onReward: levelModel.manipulationAction,
            ),
          ),
          Flexible(
            flex: 1,
            // Conditionally show the correct hint button based on the level type
            child: levelModel.currentLevel?.hintType == 'fact'
                ? AdButton(
                    productId: highlightProductId,
                    overrideTitle: 'Fact',
                    onReward: levelModel.showFactAction)
                : AdButton(
                    productId: highlightProductId,
                    overrideTitle: 'Highlight',
                    onReward: levelModel.highlightAction),
          ),
        ],
      );
    });
  }
}
