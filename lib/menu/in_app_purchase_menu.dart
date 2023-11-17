import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:operation_hermes/C.dart';
import 'package:operation_hermes/in_app_purchase/in_app_purchase_controller.dart';
import 'package:operation_hermes/in_app_purchase/purchases/purchasable_product.dart';
import 'package:provider/provider.dart';

class InAppPurchaseMenuDialog extends StatelessWidget {
  const InAppPurchaseMenuDialog({super.key});

  IconData _getIconForPurchase(String productId) {
    switch (productId) {
      case C.ALL_IN_PACK || C.ALL_IN_PACK_IOS:
        return Icons.workspace_premium_outlined;
      case C.REMOVE_3 || C.REMOVE_3_IOS:
        return Icons.looks_3_outlined;
      case C.HIGHLIGHT || C.HIGHLIGHT_IOS:
        return Icons.highlight_alt_outlined;
      case C.MANIPULATE || C.MANIPULATE_IOS:
        return Icons.zoom_out_outlined;
      case C.NO_AD_BREAKS || C.NO_AD_BREAKS_IOS:
        return Icons.tv_off;
      default:
        return Icons.workspace_premium_outlined;
    }
  }

  String _getShortSubtitle(String productId) {
    switch (productId) {
      case C.ALL_IN_PACK || C.ALL_IN_PACK_IOS:
        return "All items below";
      case C.REMOVE_3 || C.REMOVE_3_IOS:
        return "Remove unneeded letters";
      case C.HIGHLIGHT || C.HIGHLIGHT_IOS:
        return "Show letter in picture";
      case C.MANIPULATE || C.MANIPULATE_IOS:
        return "Zoom and rotate";
      case C.NO_AD_BREAKS || C.NO_AD_BREAKS_IOS:
        return "No ads between levels";
      default:
        return "";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<InAppPurchaseController>(
      builder: (context, inAppPurchaseController, _) {
        var products = inAppPurchaseController.products.sortedBy((element) => element.productName);
        final allInPack = inAppPurchaseController.products
            .firstWhereOrNull((element) => element.id == C.ALL_IN_PACK || element.id == C.ALL_IN_PACK_IOS);
        final purchasesCount = inAppPurchaseController.products
            .where((element) => element.status == ProductStatus.purchased)
            .length;
        if (allInPack?.status != ProductStatus.purchased && purchasesCount >= 2)
        {
          products.removeWhere((element) => element.id == C.ALL_IN_PACK || element.id == C.ALL_IN_PACK_IOS);
        }
      
        return Dialog(
            child: ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 8.0),
          shrinkWrap: true,
          itemCount: products.length,
          itemBuilder: (context, index) {
            final product = products[index];
            return ListTile(
              leading: product.status == ProductStatus.pending
                  ? const Icon(Icons.change_circle_outlined)
                  : Icon(_getIconForPurchase(product.id)),
              title: Text(product.productName),
              subtitle: (product.status == ProductStatus.purchased ||
                      allInPack?.status == ProductStatus.purchased) ? null : Text(_getShortSubtitle(product.id)),
              trailing: (product.status == ProductStatus.purchased ||
                      allInPack?.status == ProductStatus.purchased)
                  ? Icon(
                      Icons.done_outline_rounded,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.38),
                    )
                  : Text(product.price),
              enabled: (product.status == ProductStatus.pending ||
                      product.status == ProductStatus.purchased ||
                      allInPack?.status == ProductStatus.purchased)
                  ? false
                  : true,
              onTap:
               () async {
                inAppPurchaseController.buy(product.id);
                //Navigator.of(context).pop(); // Close the dialog
              },
            );
          },
          separatorBuilder: (context, index) {
            // Add a Divider between items
            if (products[index].id == C.ALL_IN_PACK || products[index].id == C.ALL_IN_PACK_IOS) {
              return Divider(color: Theme.of(context).colorScheme.primary);
            } else {
              return const Divider();
            }
          },
        ));
      },
    );
  }
}
