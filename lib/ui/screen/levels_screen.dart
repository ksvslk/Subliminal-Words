import 'package:flutter/material.dart';
import 'package:operation_hermes/change_notifier/level_model.dart';
import 'package:operation_hermes/controller/firebase_service.dart';
import 'package:operation_hermes/persistence/progress_persistence.dart';
import 'package:operation_hermes/data/pack.dart';
import 'package:operation_hermes/data/sw_level.dart';
import 'package:provider/provider.dart';

class LevelsScreen extends StatefulWidget {
  final Pack pack;
  const LevelsScreen({super.key, required this.pack});

  @override
  State<LevelsScreen> createState() => _LevelsScreenState();
}

class _LevelsScreenState extends State<LevelsScreen> {
  // We only need the future for *completed* levels.
  // The levels list will come from the StreamProvider.
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

    // 1. Watch for the Stream itself.
    final levelsStream = context.watch<Stream<List<SWLevel>>>();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.pack.name),
      ),
      // 2. Use a StreamBuilder for the levels
      body: StreamBuilder<List<SWLevel>>(
        stream: levelsStream,
        builder: (context, levelsSnapshot) {
          
          // 3. This check handles loading.
          // Note: getLevelsStream WILL show a brief load because
          // it has to load local JSON assets, which is an async 'await'.
          if (levelsSnapshot.connectionState == ConnectionState.waiting && !levelsSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (levelsSnapshot.hasError) {
            return Center(child: Text('Error: ${levelsSnapshot.error}'));
          }
          final levels = levelsSnapshot.data;
          if (levels == null || levels.isEmpty) {
            return const Center(child: Text('No levels found in this pack.'));
          }

          // 4. Nest a FutureBuilder for the completion status
          return FutureBuilder<Set<String>>(
            future: _completedLevelsFuture,
            builder: (context, completedSnapshot) {
              // We don't need a spinner, just build with empty data
              final completedLevels = completedSnapshot.data ?? <String>{};

              final screenWidth = MediaQuery.of(context).size.width;
              final crossAxisCount = (screenWidth / 120).floor().clamp(3, 6);

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
                    // --- Completed Level Style ---
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
                            color: colorScheme.onPrimary.withOpacity(0.15),
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
                                    color: Colors.black.withOpacity(0.2),
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
                    // --- Default Level Style ---
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
      ),
    );
  }
}