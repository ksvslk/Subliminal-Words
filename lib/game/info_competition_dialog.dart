import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:operation_hermes/competition/competition_controller.dart';
import 'package:operation_hermes/game/letter_box.dart';
import 'package:operation_hermes/game/model/competition_data.dart';
import 'package:operation_hermes/game/model/level_model.dart';
import 'package:operation_hermes/games_services/games_services.dart';
import 'package:provider/provider.dart';

class InfoCompetitionDialog extends StatelessWidget {
  const InfoCompetitionDialog({Key? key}) : super(key: key);

  void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _copyToClipboard(BuildContext context, String promoCode) {
    Clipboard.setData(ClipboardData(text: promoCode));
    Navigator.of(context).pop();
    _showSnackBar(context, 'Copied to clipboard');
  }

  Widget getEmptyResult(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
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
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'Competition',
                style: TextStyle(
                  fontSize:
                      Theme.of(context).textTheme.headlineMedium?.fontSize,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(height: 16.0),
          const Text("Something went wrong."),
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
  }

  @override
  Widget build(BuildContext context) {
    final maxDialogWidth = MediaQuery.of(context).size.width * 0.9;
    final maxDialogHeight = MediaQuery.of(context).size.height * 0.9;

    final competitionController = context.read<CompetitionController>();
    final persistence = context.read<LevelModel>();

    // Use FutureBuilder to fetch competition data
    return Dialog(
      backgroundColor: Colors.transparent,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return FutureBuilder<List<dynamic>>(
            future: Future.wait([
              competitionController.getCompetitionData(),
              persistence.getMaxLevelNr()
            ]),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(),
                );
              } else if (snapshot.hasError) {
                return const Center(
                  child: Text('Error loading competition data.'),
                );
              } else if (snapshot.hasData && snapshot.data != null) {
                // The snapshot data will be a List containing the results of each Future
                final competitionData = snapshot.data![0] as CompetitionData?;
                final maxLevel = snapshot.data![1] as int;

                if (competitionData != null) {
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
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Text(
                              'Competition',
                              style: TextStyle(
                                fontSize: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.fontSize,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onPrimaryContainer,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        ...getWidgetsByState(
                            context, competitionData, maxLevel),
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
                } else {
                  return getEmptyResult(context);
                }
              } else {
                return getEmptyResult(context);
              }
            },
          );
        },
      ),
    );
  }

  // Modify this method to take competitionData as a parameter
  List<Widget> getWidgetsByState(
      BuildContext context, CompetitionData competitionData, int maxLevel) {
    if (competitionData.finished) {
      return [
        Flexible(
          flex: 1,
          child: Text(
            competitionData.promoCode != ""
                ? 'Well done! You finished with a prize promo code: '
                : 'Good job, but promo codes are already given out.',
            style: TextStyle(
              fontSize: Theme.of(context).textTheme.bodyLarge?.fontSize,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        competitionData.promoCode != ""
            ? Flexible(
                flex: 1,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 0),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Expanded(
                          child: Text(
                            competitionData.promoCode,
                            style: TextStyle(
                              fontSize: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.fontSize,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy),
                          onPressed: () => _copyToClipboard(
                              context, competitionData.promoCode),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            : const Spacer()
      ];
    } else {
      if (competitionData.enrolled) {
        return [
          Text(
            'You have completed $maxLevel from ${CompetitionController.competitionGoalLevel} levels. Keep going!',
            style: TextStyle(
              fontSize: Theme.of(context).textTheme.bodyLarge?.fontSize,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 0),
            child: LinearProgressIndicator(
              color: Theme.of(context).colorScheme.onPrimaryContainer,
              backgroundColor: Theme.of(context)
                  .colorScheme
                  .secondaryContainer
                  .blendWith(Theme.of(context).colorScheme.primary, 0.25),
              value: maxLevel / CompetitionController.competitionGoalLevel,
            ),
          ),
        ];
      } else {
        return [const Text("Did not qualify to enroll.")];
      }
    }
  }
}

// Modify the showInfoCompetitionDialog to accept playerId
void showInfoCompetitionDialog(BuildContext context) {
  showDialog(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black87,
    builder: (BuildContext context) {
      return const InfoCompetitionDialog();
    },
  );
}
