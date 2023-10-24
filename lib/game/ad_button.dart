import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:operation_hermes/ads/ads_controller.dart';
import 'package:operation_hermes/audio/audio_controller.dart';
import 'package:operation_hermes/audio/sounds.dart';
import 'package:operation_hermes/game/model/level_model.dart';
import 'package:operation_hermes/in_app_purchase/in_app_purchase_controller.dart';
import 'package:operation_hermes/in_app_purchase/purchases/purchasable_product.dart';
import 'package:provider/provider.dart';
import '../C.dart' as C;

class AdButton extends StatelessWidget {
  static final _log = Logger('AdButton');

  const AdButton({super.key, required this.productId});

  final String productId;

  (
    Function()?,
    (String, Icon),
  ) getCallbackAndText(
      BuildContext context,
      InAppPurchaseController iapController,
      AdsController adsController,
      bool manipulationExhausted,
      bool remove3Available,
      AudioController audioController,
      LevelModel levelModel) {
    // ✔︎ Erandid:
    // MANIPULATION - Kui zoom juba avatud - DISABLED, Exhausted
    // REMOVE_3 - Kui rohkem tähti enam ei saa eemaldada - DISABLED, Exhausted
    if ((productId == C.MANIPULATE && manipulationExhausted) ||
        (productId == C.REMOVE_3 && !remove3Available)) {
          _log.log(Level.INFO, "Applied - $productId");
      return (null, ('Applied', const Icon(Icons.done_rounded)));
    }

    // ✔︎ Kui pole products nimekirjas - Disabled, loading.
    final product = iapController.products
        .firstWhereOrNull((element) => element.id == productId);
    if (product == null) {
      _log.log(Level.INFO, "Loading (empty products) - $productId");
      return (null, ('Loading', const Icon(Icons.hourglass_top_outlined)));
    }

    // ✔︎ Kui on ostetud või on ALL IN ostetud - ENABLED, Product name ✪
    final allInPack = iapController.products
        .firstWhereOrNull((element) => element.id == C.ALL_IN_PACK);
    if (product.status == ProductStatus.purchased ||
        allInPack?.status == ProductStatus.purchased) {
           _log.log(Level.INFO, "Purchased (or all in ${allInPack?.status.name}) - $productId");
      return (
        getSuccessfulAction(audioController, levelModel),
        (product.productName, const Icon(Icons.bolt))
      );
    }

    // ✔︎ Kui pole ostetud ja kui pole reklaami näidata - DISABLED, product name
    if (product.status != ProductStatus.purchased &&
        !adsController.isAdAvailable()) {
          _log.log(Level.INFO, "No purchase, no ads - $productId");
      return (null, (product.productName, const Icon(Icons.hourglass_top_outlined)));
    }

    // ✔︎ Kui pole ostetud ja ON reklaami näidata - ENABLED, Product name ▷
    if (product.status != ProductStatus.purchased &&
        adsController.isAdAvailable()) {
          _log.log(Level.INFO, "No purchase, ADS available! - $productId");
      callback() => {
            adsController.showRewardedAd(() {
              getSuccessfulAction(audioController, levelModel)?.call();
            })
          };
      return (callback, (product.productName, const Icon(Icons.slideshow_rounded)));
    }

    throw StateError(
        "'¯\_(ツ)_/¯' -> Product: $productId, ${product.status.name}, Ad: ${adsController.isAdAvailable()}, Iap controller: ${iapController.products.map((e) => e.id)}");
  }


  Function()? getSuccessfulAction(
      AudioController audioController, LevelModel levelModel) {
    switch (productId) {
      case C.REMOVE_3:
        return () {
          audioController.playSfx(SfxType.wrong);
          levelModel.remove3Action();
        };
      case C.MANIPULATE:
        return () {
          audioController.playSfx(SfxType.rewardGiven);
          levelModel.manipulationAction();
        };
      case C.HIGHLIGHT:
        return () {
          audioController.playSfx(SfxType.rewardGiven);
          levelModel.highlightAction();
        };
      default:
        return () {};
    }
  }


  @override
  Widget build(BuildContext context) {
    final audioController = context.read<AudioController>();
    return Consumer<AdsController>(builder: (context, adsController, _) {
      _log.log(Level.INFO, "Building AdsController");
      return Consumer<InAppPurchaseController>(
          builder: (context, iapController, _) {
      _log.log(Level.INFO, "Building InAppPurchaseController");
        return Consumer<LevelModel>(builder: (context, levelModel, _) {
        _log.log(Level.INFO, "Building LevelModel");
          final callbackAndText = getCallbackAndText(context, iapController,
              adsController, levelModel.manipulationEnabled, levelModel.remove3Available, audioController, levelModel);
          return Padding(
            padding: const EdgeInsets.all(4.0),
            child: FilledButton.icon(
              onPressed: !levelModel.levelCompleted ? callbackAndText.$1 : null,
              icon: callbackAndText.$2.$2,
              label: FittedBox(
                fit: BoxFit.fitWidth,
                child: Text(
                  callbackAndText.$2.$1,
                  maxLines: 1,
                  style: TextStyle(
                    fontFamily: DefaultTextStyle.of(context).style.fontFamily,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        });
      });
    });
  }
}
