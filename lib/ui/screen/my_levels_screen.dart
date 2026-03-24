import 'package:flutter/material.dart';
import 'package:operation_hermes/change_notifier/level_model.dart';
import 'package:operation_hermes/controller/firebase_service.dart';
import 'package:operation_hermes/data/sw_level.dart';
import 'package:operation_hermes/data/user_level_metadata.dart';
import 'package:operation_hermes/ui/screen/create_level_screen.dart';
import 'package:provider/provider.dart';

class MyLevelsScreen extends StatelessWidget {
  const MyLevelsScreen({super.key});

  Future<void> _openEditor(BuildContext context, {SWLevel? level}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<bool>(
        builder: (_) => CreateLevelScreen(initialLevel: level),
      ),
    );
  }

  Future<void> _playLevel(BuildContext context, SWLevel level) async {
    await context.read<LevelModel>().loadLevelFromSelection(level);
    if (context.mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _submitLevel(BuildContext context, SWLevel level) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context
          .read<FirebaseService>()
          .submitUserLevelForReview(level.documentId);
      messenger.showSnackBar(
        const SnackBar(content: Text('Level submitted for review.')),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final firebaseService = context.read<FirebaseService>();
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('My Levels')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context),
        icon: const Icon(Icons.draw_outlined),
        label: const Text('Create'),
      ),
      body: StreamBuilder<List<SWLevel>>(
        stream: firebaseService.getMyLevelsStream(),
        builder: (context, snapshot) {
          final levels = snapshot.data ?? const <SWLevel>[];

          if (snapshot.connectionState == ConnectionState.waiting &&
              levels.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (levels.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(Icons.auto_awesome_motion_outlined, size: 48),
                    const SizedBox(height: 16),
                    const Text(
                      'You do not have any custom levels yet.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => _openEditor(context),
                      icon: const Icon(Icons.draw_outlined),
                      label: const Text('Create Your First Level'),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: levels.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final level = levels[index];
              final statusLabel =
                  UserLevelSubmissionStatus.labelFor(level.submissionStatus);
              final hasPuzzleImage = level.hasReviewReadyPuzzleImage;

              return Card(
                elevation: 0,
                color: colorScheme.surfaceContainerLow,
                surfaceTintColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: BorderSide(color: colorScheme.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              level.name,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          Chip(
                            label: Text(statusLabel),
                            backgroundColor: colorScheme.secondaryContainer,
                            labelStyle: TextStyle(
                              color: colorScheme.onSecondaryContainer,
                              fontWeight: FontWeight.w700,
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Type: ${UserLevelEditorMode.labelFor(level.editorMode)}',
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                      if (level.creatorName.isNotEmpty)
                        Text(
                          'Level by ${level.creatorName}',
                          style: TextStyle(color: colorScheme.onSurfaceVariant),
                        ),
                      if (!hasPuzzleImage) ...<Widget>[
                        const SizedBox(height: 6),
                        Text(
                          'Add the real puzzle image before playing or submitting.',
                          style: TextStyle(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: hasPuzzleImage
                                  ? () => _playLevel(context, level)
                                  : null,
                              icon: const Icon(Icons.play_arrow_outlined),
                              label: const Text('Play'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: level.isLocked
                                  ? null
                                  : () => _openEditor(context, level: level),
                              icon: const Icon(Icons.edit_outlined),
                              label: const Text('Edit'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: !hasPuzzleImage ||
                                      level.isLocked ||
                                      level.submissionStatus ==
                                          UserLevelSubmissionStatus
                                              .pendingReview
                                  ? null
                                  : () => _submitLevel(context, level),
                              icon: const Icon(Icons.publish_outlined),
                              label: const Text('Submit'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
