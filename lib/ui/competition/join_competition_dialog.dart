import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:operation_hermes/controller/competition_controller.dart';

void showJoinedCompetitionDialog(BuildContext context) {
  showDialog(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black87,
    builder: (BuildContext context) {
      return const CompetitionDialog();
    },
  );
}

class CompetitionDialog extends StatelessWidget {
  const CompetitionDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final maxDialogWidth = MediaQuery.of(context).size.width * 0.9;
    final maxDialogHeight = MediaQuery.of(context).size.height * 0.9;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Container(
            padding: const EdgeInsets.all(20),
            constraints: BoxConstraints(
              maxWidth: maxDialogWidth,
              maxHeight: maxDialogHeight,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Theme.of(context).colorScheme.surfaceContainer,
                  Theme.of(context).colorScheme.primaryContainer,
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 10,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Flexible(
                  flex: 1,
                  child: Lottie.asset(
                    'assets/animation/paperplane.json',
                    width: constraints.maxWidth * 0.6,
                    height: constraints.maxHeight * 0.25,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 16),
                Flexible(
                  flex: 1,
                  child: Text(
                    'Level Completion Challenge',
                    style: TextStyle(
                      fontSize:
                          Theme.of(context).textTheme.headlineMedium?.fontSize,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 16),
                Flexible(
                  flex: 1,
                  child: Text(
                    'Be among the players to complete ${CompetitionController.competitionGoalLevel} first levels in Chapter I before others and win a promo code!',
                    style: TextStyle(
                      fontSize: Theme.of(context).textTheme.bodyLarge?.fontSize,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 16),
                const Flexible(
                  flex: 1,
                  child: Text(
                    'Limited number of prizes!',
                  ),
                ),
                const SizedBox(height: 24.0),
                Flexible(
                  flex: 1,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
