
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/material.dart';
import 'package:operation_hermes/config/C.dart';
import 'package:operation_hermes/change_notifier/level_model.dart';
import 'package:operation_hermes/controller/shimmer_placeholders.dart';
import 'package:operation_hermes/data/progress_achievement.dart';
import 'package:operation_hermes/ui/ad_button.dart';
import 'package:provider/provider.dart';

class HintBar extends StatelessWidget {
  const HintBar({super.key});

  @override
  Widget build(BuildContext context) {

    final jsonString = FirebaseRemoteConfig.instance.getString(C.progressAchievemetns);
    final list = jsonDecode(jsonString) as List<dynamic>;
    list.forEach((element) {
      final c = ProgressAchievement.fromMap(element);
      print(c.name);
    });

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
            // Conditionally show the correct hint button based on the level type
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
