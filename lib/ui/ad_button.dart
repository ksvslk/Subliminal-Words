import 'package:auto_size_text/auto_size_text.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:logging/logging.dart';
import 'package:operation_hermes/change_notifier/level_model.dart';
import 'package:operation_hermes/config/C.dart';
import 'package:operation_hermes/config/sounds.dart';
import 'package:operation_hermes/controller/ads_controller.dart';
import 'package:operation_hermes/controller/audio_controller.dart';
import 'package:operation_hermes/controller/in_app_purchase_controller.dart';
import 'package:operation_hermes/data/purchasable_product.dart';
import 'package:provider/provider.dart';

class AdButton extends StatelessWidget {
  static final _log = Logger('AdButton');

  const AdButton(
      {super.key, required this.productId, this.overrideTitle, required this.onReward});

  final String productId;
  final String? overrideTitle;
  final VoidCallback onReward;

  (
    Function()?,
    (String, Icon, bool),
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
    if (((productId == C.MANIPULATE || productId == C.MANIPULATE_IOS) &&
            manipulationExhausted) ||
        ((productId == C.REMOVE_3 || productId == C.REMOVE_3_IOS) &&
            !remove3Available)) {
      _log.log(Level.INFO, "Applied - $productId");
      return (null, ('Applied', const Icon(Icons.done_rounded), false));
    }

    // ✔︎ Kui pole products nimekirjas - Disabled, loading.
    var product = iapController.products
        .firstWhereOrNull((element) => element.id == productId);
    if (product == null) {
      _log.log(Level.INFO, "Loading (empty products) - $productId");

      // Create placeholder product if not found in iapController.products
      if (overrideTitle == 'Remove 3' || productId == C.REMOVE_3 || productId == C.REMOVE_3_IOS) {
        product = PurchasableProduct(ProductDetails(
            id: productId,
            title: "Remove 3",
            description: "",
            price: "",
            rawPrice: -1,
            currencyCode: ""));
        product.status = ProductStatus.purchasable;
      } else if (productId == C.MANIPULATE || productId == C.MANIPULATE_IOS) {
        product = PurchasableProduct(ProductDetails(
            id: productId,
            title: "Manipulate",
            description: "",
            price: "",
            rawPrice: -1,
            currencyCode: ""));
        product.status = ProductStatus.purchasable;
      } else if (productId == C.HIGHLIGHT || productId == C.HIGHLIGHT_IOS) {
        product = PurchasableProduct(ProductDetails(
            id: productId,
            title: overrideTitle ?? "Highlight",
            description: "",
            price: "",
            rawPrice: -1,
            currencyCode: ""));
        product.status = ProductStatus.purchasable;
      }
    }

    // ✔︎ Kui on ostetud või on ALL IN ostetud - ENABLED, Product name ✪
    final allInPack = iapController.products.firstWhereOrNull((element) =>
        element.id == C.ALL_IN_PACK || element.id == C.ALL_IN_PACK_IOS);
    if (product?.status == ProductStatus.purchased ||
        allInPack?.status == ProductStatus.purchased) {
      _log.log(Level.INFO,
          "Purchased (or all in ${allInPack?.status.name}) - $productId");
      return (
        onReward,
        (overrideTitle ?? product?.productName ?? "", const Icon(Icons.touch_app), false)
      );
    }

    // ✔︎ Kui pole ostetud ja kui pole reklaami näidata - DISABLED, product name
    if (product?.status != ProductStatus.purchased &&
        !adsController.isAdAvailable()) {
      _log.log(Level.INFO, "No purchase, no ads - $productId");
      return (
        null,
        (
          overrideTitle ?? product?.productName ?? "",
          const Icon(Icons.hourglass_top_outlined),
          false
        )
      );
    }

    // ✔︎ Kui pole ostetud ja ON reklaami näidata - ENABLED, Product name ▷
    if (product?.status != ProductStatus.purchased &&
        adsController.isAdAvailable()) {
      _log.log(Level.INFO, "No purchase, ADS available! - $productId");
      callback() => {
            adsController.showRewardedAd(() {
              onReward();
            })
          };
      return (
        callback,
        (overrideTitle ?? product?.productName ?? "", const Icon(Icons.slideshow_rounded), true)
      );
    }

    // Fallback: If none of the above conditions are met, return a default disabled state.
    _log.warning("AdButton: No matching state found for productId: $productId. Returning default disabled state.");
    return (
      null, // No action
      ('Unavailable', const Icon(Icons.error_outline), false) // Default disabled state
    );
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
          const minFontSize = 2.0;
          _log.log(Level.INFO, "Building LevelModel");
          final callbackAndText = getCallbackAndText(
              context,
              iapController,
              adsController,
              levelModel.manipulationEnabled,
              levelModel.remove3Available,
              audioController,
              levelModel);
          return levelModel.levelCompleted ? const SizedBox.expand() : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.0),
              child: Card(
                clipBehavior: Clip.hardEdge,
                child: InkWell(
                  splashColor:
                      Theme.of(context).colorScheme.tertiary.withAlpha(30),
                  onTap: !levelModel.levelCompleted ? callbackAndText.$1 : null,
                  child: SizedBox(
                    child: Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          callbackAndText.$2.$3
                              ? Flexible(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 2.0, vertical: 2.0),
                                    decoration: BoxDecoration(
                                      border: const Border.symmetric(),
                                      color: Theme.of(context)
                                          .colorScheme
                                          .tertiaryContainer,
                                      borderRadius: BorderRadius.circular(8.0),
                                    ),
                                    child: AutoSizeText(
                                      "WATCH AD",
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onTertiaryContainer,
                                      ),
                                      maxLines: 1,
                                      textAlign: TextAlign.center,
                                      minFontSize: minFontSize,
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink(),
                          callbackAndText.$2.$3
                              ? const SizedBox.shrink()
                              : Flexible(
                                  child: SizedBox.expand(
                                    child: FittedBox(
                                      child: callbackAndText.$2.$2,
                                    ),
                                  ),
                                ),
                          Flexible(
                              child: AutoSizeText(callbackAndText.$2.$1,
                                  maxLines: 1,
                                  textAlign: TextAlign.center,
                                  minFontSize: minFontSize)),
                        ],
                      ),
                    ),
                  ),
                ),
              ));
        });
      });
    });
  }
}