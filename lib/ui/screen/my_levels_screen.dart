import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:operation_hermes/change_notifier/level_model.dart';
import 'package:operation_hermes/controller/firebase_service.dart';
import 'package:operation_hermes/data/sw_level.dart';
import 'package:operation_hermes/data/user_level_metadata.dart';
import 'package:operation_hermes/ui/create_level_flow.dart';
import 'package:operation_hermes/ui/screen/create_level_screen.dart';
import 'package:provider/provider.dart';

class MyLevelsScreen extends StatelessWidget {
  const MyLevelsScreen({super.key});

  String _friendlySubmitError(Object error) {
    final message =
        error.toString().replaceFirst('Exception: ', '').toLowerCase();
    if (message.contains('signed in') ||
        message.contains('permission') ||
        message.contains('unauth') ||
        message.contains('forbidden')) {
      return 'Could not submit this level right now. Please reopen Subliminal Words and try again.';
    }
    if (message.contains('network') ||
        message.contains('connection') ||
        message.contains('timed out') ||
        message.contains('timeout') ||
        message.contains('temporarily unavailable') ||
        message.contains('service unavailable')) {
      return 'Could not submit this level right now. Check your connection and try again.';
    }
    return 'Could not submit this level for review right now. Please try again.';
  }

  Future<void> _openEditor(BuildContext context, {SWLevel? level}) async {
    if (level == null) {
      await openCreateLevelFlow(context);
      return;
    }

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
        SnackBar(content: Text(_friendlySubmitError(error))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final firebaseService = context.read<FirebaseService>();
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const AutoSizeText(
          'My Levels',
          maxLines: 1,
          minFontSize: 14,
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context),
        icon: const Icon(Icons.draw_outlined),
        label: const AutoSizeText(
          'Create',
          maxLines: 1,
          minFontSize: 10,
        ),
      ),
      body: StreamBuilder<List<SWLevel>>(
        stream: firebaseService.getMyLevelsStream(),
        builder: (context, snapshot) {
          final levels = snapshot.data ?? const <SWLevel>[];

          if (snapshot.connectionState == ConnectionState.waiting &&
              levels.isEmpty) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      CircularProgressIndicator(
                        color: colorScheme.primary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Loading your levels...',
                        textAlign: TextAlign.center,
                        style: textTheme.titleMedium?.copyWith(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          if (snapshot.hasError && levels.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        Icons.cloud_off_outlined,
                        size: 48,
                        color: colorScheme.onSurface,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Could not load your levels right now.',
                        textAlign: TextAlign.center,
                        style: textTheme.titleMedium?.copyWith(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Check your connection and reopen My Levels.',
                        textAlign: TextAlign.center,
                        style: textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          if (levels.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        Icons.auto_awesome_motion_outlined,
                        size: 48,
                        color: colorScheme.onSurface,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'You do not have any custom levels yet.',
                        textAlign: TextAlign.center,
                        style: textTheme.titleMedium?.copyWith(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.w700,
                        ),
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
                color: colorScheme.surfaceContainerHigh,
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
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              level.name.isEmpty ? 'Untitled Level' : level.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.titleMedium?.copyWith(
                                color: colorScheme.onSurface,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              statusLabel,
                              style: textTheme.labelMedium?.copyWith(
                                color: colorScheme.onSecondaryContainer,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Type: ${UserLevelEditorMode.labelFor(level.editorMode)}',
                        style: textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (level.creatorName.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 4),
                        Text(
                          'Level by ${level.creatorName}',
                          style: textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (!hasPuzzleImage) ...<Widget>[
                        const SizedBox(height: 8),
                        Text(
                          'Add the real puzzle image before playing or submitting.',
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: <Widget>[
                          OutlinedButton.icon(
                            onPressed:
                                hasPuzzleImage ? () => _playLevel(context, level) : null,
                            icon: const Icon(Icons.play_arrow_outlined),
                            label: const Text('Play'),
                          ),
                          OutlinedButton.icon(
                            onPressed: level.isLocked
                                ? null
                                : () => _openEditor(context, level: level),
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('Edit'),
                          ),
                          FilledButton.icon(
                            onPressed: !hasPuzzleImage ||
                                    level.isLocked ||
                                    level.submissionStatus ==
                                        UserLevelSubmissionStatus.pendingReview
                                ? null
                                : () => _submitLevel(context, level),
                            icon: const Icon(Icons.publish_outlined),
                            label: const Text('Submit'),
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
