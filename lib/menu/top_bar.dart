import 'package:flutter/material.dart';
import 'package:operation_hermes/menu/in_app_purchase_menu.dart';
import 'package:operation_hermes/menu/settings_menu.dart';
import 'package:operation_hermes/menu/story_bottom_sheet.dart';
import 'package:operation_hermes/menu/story_tablo.dart';

class TopBar extends StatelessWidget {
  const TopBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        const Flexible(flex: 1, child: SettingsMenu()),
        Flexible(
            flex: 1,
            child: IconButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (BuildContext context) {
                      return const InAppPurchaseMenuDialog();
                    },
                  );
                },
                icon: const Icon(Icons.add_shopping_cart_outlined))),
        Flexible(
          flex: 6,
          child: Container(
              decoration: BoxDecoration(
                borderRadius:
                    BorderRadius.circular(10), // Adjust the radius as needed
                border: Border.all(
                    color: Theme.of(context)
                        .colorScheme
                        .secondary), // Border style
              ),
              padding: const EdgeInsets.all(8), // Padding inside the container
              child: GestureDetector(
                child: const StoryTablo(),
                onTap: () {
                  showModalBottomSheet(
                    isScrollControlled: true,
                    context: context, builder:(context) => const StoryBottomSheet());
                },
              )),
        ),
      ],
    );
  }
}
