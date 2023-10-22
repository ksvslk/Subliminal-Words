import 'package:flutter/material.dart';
import 'package:operation_hermes/in_app_purchase/in_app_purchase_controller.dart';
import 'package:operation_hermes/in_app_purchase/purchases/purchasable_product.dart';
import 'package:provider/provider.dart';

class InAppPurchaseMenuDialog extends StatelessWidget {
  const InAppPurchaseMenuDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<InAppPurchaseController>(
      builder: (context, inAppPurchaseController, _) {
        final products = inAppPurchaseController.products;
        return Dialog(
            child: ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 8.0),
          shrinkWrap: true,
          itemCount: products.length,
          itemBuilder: (context, index) {
            final product = products[index];
            return ListTile(
              leading: product.status == ProductStatus.pending ? const Icon(Icons.change_circle_outlined) : const Icon(Icons.workspace_premium),
              title: Text(product.productName),
              trailing: Text(product.price),
              enabled: product.status == ProductStatus.pending ? false : true,
              onTap: () async {
                inAppPurchaseController.buy(product.id);
                //Navigator.of(context).pop(); // Close the dialog
              },
            );
          },
          separatorBuilder: (context, index) {
            // Add a Divider between items
            return const Divider();
          },
        ));
      },
    );
  }
}
