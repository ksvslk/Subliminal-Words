import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';

class FreudDialog extends StatelessWidget {
  const FreudDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return 
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Flexible(
          flex: 2,
          child: Container(
            margin: const EdgeInsets.all(
                8.0), 
            padding: const EdgeInsets.all(
                20.0), 
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .surface, 
              border: Border.all(
                  color: Theme.of(context).colorScheme.onSurface,
                  width: 2.0), 
              borderRadius: BorderRadius.circular(10.0), 
            ),
            child: AutoSizeText(
              "I'm glad you're here, please take a seat on the sofa. What word do you see?",
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: Theme.of(context).textTheme.bodyMedium?.fontSize),
            ),
          ),
        ),
        Flexible(
          flex: 1,
          child: Container(
            margin: const EdgeInsets.all(
                8.0),
            child: Image.asset(
              'assets/other/freud200.png',
              fit: BoxFit.scaleDown,
            ),
          ),
        ),
      ]);
  }
}
