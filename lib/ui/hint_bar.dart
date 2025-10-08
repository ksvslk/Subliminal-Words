
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:operation_hermes/config/C.dart';
import 'package:operation_hermes/ui/ad_button.dart';

class HintBar extends StatelessWidget {
  const HintBar({super.key});

  @override
  Widget build(BuildContext context) {
    final remove3ProductId = Platform.isAndroid ? C.REMOVE_3 : C.REMOVE_3_IOS;
    final manipulateProductId = Platform.isAndroid ? C.MANIPULATE : C.MANIPULATE_IOS;
    final higlightProductId = Platform.isAndroid ? C.HIGHLIGHT : C.HIGHLIGHT_IOS;
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        Flexible(
          flex: 1,
          child: AdButton(productId: remove3ProductId),
        ),
        Flexible(
          flex: 1,
          child: AdButton(productId: manipulateProductId),
        ),
        Flexible(
          flex: 1,
          child: AdButton(productId: higlightProductId),
        ),
      ],
    );
  }
}
