import 'package:flutter/material.dart';
import 'package:operation_hermes/menu/story_tablo.dart';

class TopBar extends StatelessWidget {
  const TopBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        Flexible(
            flex: 1,
            child:
                IconButton(onPressed: () {}, icon: const Icon(Icons.settings))),
        Flexible(
            flex: 1,
            child: IconButton(
                onPressed: () {
                  //showMenu(context);
                },
                icon: const Icon(Icons.add_shopping_cart_outlined))),
        Flexible(
          flex: 6,
          child: Container(
              decoration: BoxDecoration(
                borderRadius:
                    BorderRadius.circular(10), // Adjust the radius as needed
                border: Border.all(
                    color:
                        Theme.of(context).colorScheme.outline), // Border style
              ),
              padding: const EdgeInsets.all(8), // Padding inside the container
              child: const StoryTablo()),
        ),
      ],
    );
  }
}
