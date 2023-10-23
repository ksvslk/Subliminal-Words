import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:operation_hermes/in_app_purchase/in_app_purchase_controller.dart';
import 'package:operation_hermes/in_app_purchase/purchases/purchasable_product.dart';
import 'package:provider/provider.dart';
import '../C.dart' as C;

class InAppPurchaseMenuDialog extends StatelessWidget {
  const InAppPurchaseMenuDialog({super.key});

  IconData _getIconForPurchase(String productId) {
    switch (productId) {
      case C.ALL_IN_PACK:
        return Icons.workspace_premium_outlined;
      case C.REMOVE_3:
        return Icons.looks_3_outlined;
      case C.HIGHLIGHT:
        return Icons.highlight_alt_outlined;
      case C.MANIPULATE:
        return Icons.zoom_out_outlined;
      case C.NO_AD_BREAKS:
        return Icons.tv_off;
      default:
        return Icons.workspace_premium_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<InAppPurchaseController>(
      builder: (context, inAppPurchaseController, _) {
        final products = inAppPurchaseController.products;
        final allInPack =
            products.firstWhereOrNull((element) => element.id == C.ALL_IN_PACK);
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
              trailing: (product.status == ProductStatus.purchased ||
                      allInPack?.status == ProductStatus.purchased)
                  ? Icon(
                      Icons.done_outline_rounded,
                      color: Theme.of(context).colorScheme.primary,
                    )
                  : Text(product.price),
              enabled: (product.status == ProductStatus.pending ||
                      product.status == ProductStatus.purchased ||
                      allInPack?.status == ProductStatus.purchased)
                  ? false
                  : true,
              onTap: () async {
                inAppPurchaseController.buy(product.id);
                //Navigator.of(context).pop(); // Close the dialog
              },
            );
          },
          separatorBuilder: (context, index) {
            // Add a Divider between items
            if (products[index].id == C.ALL_IN_PACK) {
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
