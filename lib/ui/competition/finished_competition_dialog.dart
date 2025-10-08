import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:operation_hermes/ui/competition/won_competition_dialog.dart';

void showFinishedCompetitionDialog(BuildContext context) {
  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black87,
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (BuildContext buildContext, Animation<double> animation,
        Animation secondaryAnimation) {
      return ScaleTransition(
        scale: Tween<double>(begin: 0.5, end: 1.0).animate(
          CurvedAnimation(
            parent: animation,
            curve: Curves.fastOutSlowIn,
          ),
        ),
        child: const FinishedCompetitionDialog(),
      );
    },
  );
}

class FinishedCompetitionDialog extends StatefulWidget {
  const FinishedCompetitionDialog({super.key});

  @override
  _FinishedCompetitionDialogState createState() =>
      _FinishedCompetitionDialogState();
}

class _FinishedCompetitionDialogState extends State<FinishedCompetitionDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _confettiController;

  @override
  void initState() {
    super.initState();
    _confettiController =
        AnimationController(duration: const Duration(seconds: 3), vsync: this);
  }

  @override
  void dispose() {
    _confettiController.dispose();
    super.dispose();
  }

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
                  child: Lottie.network(
                    'https://lottie.host/8580f31b-d4c3-421a-b9cd-4742df98afc7/6Q3WX5f3RH.json',
                    width: constraints.maxWidth * 0.6,
                    height: constraints.maxHeight * 0.25,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 16),
                Flexible(
                  flex: 1,
                  child: Text(
                    'You are a finisher!',
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
                    'No prizes left. Share the game on social media, send screenshot to indrek@indest.ee for bonus prize!',
                    style: TextStyle(
                      fontSize: Theme.of(context).textTheme.bodyLarge?.fontSize,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    textAlign: TextAlign.center,
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
                        onPressed: () {
                          Navigator.of(context).pop();
                          showWonCompetitionDialog(context, "123");
                        },
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
