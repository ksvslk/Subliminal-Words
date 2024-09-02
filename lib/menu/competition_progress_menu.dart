import 'package:flutter/material.dart';
import 'package:operation_hermes/game/letter_box.dart'; 

class CompetitionProgressMenu extends StatelessWidget {
  final int progress;
  final int goal;

  const CompetitionProgressMenu({super.key, required this.progress, required this.goal});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints.expand(
        width: 175,
        height: 45,
      ),
      child: Row(
        children: [
          Expanded(
            child: LinearProgressIndicator(
              color: Theme.of(context).colorScheme.onPrimaryContainer,
              backgroundColor: Theme.of(context)
                  .colorScheme
                  .secondaryContainer
                  .blendWith(Theme.of(context).colorScheme.primary, 0.25),
              value: progress / goal,
            ),
          ),
          const SizedBox(width: 8.0),
          Text(
            "$progress/$goal",
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
