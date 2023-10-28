import 'package:flutter/material.dart';
import 'package:operation_hermes/game/ad_button.dart';
import '../C.dart' as C;

class HintBar extends StatelessWidget {
  const HintBar({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        Flexible(
          flex: 1,
          child: AdButton(productId: C.REMOVE_3),
        ),
        Flexible(
          flex: 1,
          child: AdButton(productId: C.MANIPULATE),
        ),
        Flexible(
          flex: 1,
          child: AdButton(productId: C.HIGHLIGHT),
        ),
      ],
    );
  }
}
