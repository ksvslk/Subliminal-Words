import 'package:flutter/material.dart';
import 'package:operation_hermes/change_notifier/level_model.dart';
import 'package:operation_hermes/controller/firebase_service.dart';
import 'package:operation_hermes/persistence/progress_persistence.dart';
import 'package:operation_hermes/data/pack.dart';
import 'package:operation_hermes/data/sw_level.dart';
import 'package:provider/provider.dart';
import 'package:operation_hermes/controller/ads_controller.dart';
import 'package:operation_hermes/controller/money_controller.dart';

class LevelsScreen extends StatefulWidget {
  final Pack pack;
  const LevelsScreen({super.key, required this.pack});

  @override
  State<LevelsScreen> createState() => _LevelsScreenState();
}

class _LevelsScreenState extends State<LevelsScreen> {
  late Future<Set<String>> _completedLevelsFuture;

  @override
  void initState() {
    super.initState();
    final progressPersistence =
        Provider.of<ProgressPersistence>(context, listen: false);
    _completedLevelsFuture = progressPersistence.getCompletedLevels();
  }

  @override
  Widget build(BuildContext context) {
    final levelModel = context.read<LevelModel>();
    final colorScheme = Theme.of(context).colorScheme;
    final service = context.read<FirebaseService>();
    final levelsStream = service.getLevelsStream(widget.pack.id);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.pack.name),
      ),
      body: StreamBuilder<List<SWLevel>>(
        stream: levelsStream,
        builder: (context, levelsSnapshot) {
          if (levelsSnapshot.connectionState == ConnectionState.waiting &&
              !levelsSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (levelsSnapshot.hasError) {
            return Center(child: Text('Error: ${levelsSnapshot.error}'));
          }
          final levels = levelsSnapshot.data;
          if (levels == null || levels.isEmpty) {
            return const Center(child: Text('No levels found in this pack.'));
          }
          return FutureBuilder<Set<String>>(
            future: _completedLevelsFuture,
            builder: (context, completedSnapshot) {
              final completedLevels = completedSnapshot.data ?? <String>{};
              final screenWidth = MediaQuery.of(context).size.width;
              final crossAxisCount = (screenWidth / 120).floor().clamp(3, 6);

              return Consumer<MoneyController?>(
                builder: (context, moneyController, _) {
                  final needsAd = moneyController?.hasAllAccess() != true;

                  return GridView.builder(
                padding: const EdgeInsets.all(16.0),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 16.0,
                  mainAxisSpacing: 16.0,
                  childAspectRatio: 1 / 1,
                ),
                itemCount: levels.length,
                itemBuilder: (context, index) {
                  final level = levels[index];
                  final bool isEnabled = level.isEnabled;
                  final bool isCompleted = completedLevels.contains(level.id);

                  Widget cardContent;

                  if (isCompleted && isEnabled) {
                    cardContent = Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [colorScheme.primary, colorScheme.tertiary],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Icon(
                            Icons.check_circle,
                            size: 125,
                            color: colorScheme.onPrimary.withAlpha(38),
                          ),
                          Center(
                            child: Text(
                              '${level.nr}',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onPrimary,
                                shadows: [
                                  Shadow(
                                    blurRadius: 2.0,
                                    color: Colors.black.withAlpha(51),
                                    offset: const Offset(1, 1),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  } else {
                    cardContent = Container(
                      color: isEnabled
                          ? colorScheme.tertiaryContainer
                          : colorScheme.surfaceContainer,
                      child: Center(
                        child: Text(
                          '${level.nr}',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: isEnabled
                                ? colorScheme.onTertiaryContainer
                                : colorScheme.onSurface.withOpacity(0.5),
                          ),
                        ),
                      ),
                    );
                  }

                  if (isEnabled && needsAd) {
                    cardContent = Stack(
                      children: [
                        Positioned.fill(child: cardContent),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Icon(
                            Icons.slideshow_rounded,
                            size: 18,
                            color: isCompleted
                                ? colorScheme.onPrimary
                                : colorScheme.onTertiaryContainer,
                          ),
                        ),
                      ],
                    );
                  }

                  return Card(
                    elevation: 2,
                    clipBehavior: Clip.antiAlias,
                    child: AbsorbPointer(
                      absorbing: !isEnabled,
                      child: InkWell(
                          onTap: () async {
                            await Future.delayed(
                                const Duration(milliseconds: 100));
                            if (!context.mounted) return;

                            levelModel.loadLevelFromSelection(level);
                            Navigator.of(context)
                                .popUntil((route) => route.isFirst);
                          },
                          child: cardContent),
                    ),
                  );
                },
              );
            },
          );
            },
          );
        },
      ),
    );
  }
}
