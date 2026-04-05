import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:operation_hermes/change_notifier/level_model.dart';
import 'package:operation_hermes/controller/ads_controller.dart';
import 'package:operation_hermes/controller/firebase_service.dart';
import 'package:operation_hermes/controller/money_controller.dart';
import 'package:operation_hermes/data/sw_level.dart';
import 'package:operation_hermes/data/user_level_metadata.dart';
import 'package:operation_hermes/ui/app_scaffold_messenger.dart';
import 'package:operation_hermes/ui/create_level_flow.dart';
import 'package:operation_hermes/ui/screen/create_level_screen.dart';
import 'package:provider/provider.dart';

enum _LevelCardAction {
  play,
  edit,
  submit,
  delete,
}

class MyLevelsScreen extends StatefulWidget {
  const MyLevelsScreen({super.key});

  @override
  State<MyLevelsScreen> createState() => _MyLevelsScreenState();
}

class _MyLevelsScreenState extends State<MyLevelsScreen> {
  String? _activeLevelActionId;
  _LevelCardAction? _activeLevelAction;

  bool _isLevelBusy(String levelId) => _activeLevelActionId == levelId;

  bool _isActionBusy(String levelId, _LevelCardAction action) =>
      _activeLevelActionId == levelId && _activeLevelAction == action;

  Future<void> _runLevelAction(
    String levelId,
    _LevelCardAction action,
    Future<void> Function() run,
  ) async {
    if (_isLevelBusy(levelId)) {
      return;
    }

    setState(() {
      _activeLevelActionId = levelId;
      _activeLevelAction = action;
    });

    try {
      await run();
    } finally {
      if (mounted &&
          _activeLevelActionId == levelId &&
          _activeLevelAction == action) {
        setState(() {
          _activeLevelActionId = null;
          _activeLevelAction = null;
        });
      }
    }
  }

  void _showActionBlocked(BuildContext context, String message) {
    showAppSnackBar(message);
  }

  String _friendlySubmitError(Object error) {
    final message =
        error
            .toString()
            .replaceFirst('Exception: ', '')
            .replaceFirst('Bad state: ', '')
            .trim()
            .toLowerCase();
    if (message.contains('safety-checked before review')) {
      return 'Open this photo level and save it again before submitting for review.';
    }
    if (message.contains('level creation is unavailable')) {
      return 'Level creation is unavailable for this account right now.';
    }
    if (message.contains('missing a creator name or answer')) {
      return 'Add the creator name and solution before submitting for review.';
    }
    if (message.contains('missing a fact hint')) {
      return 'Add a fact hint before submitting for review.';
    }
    if (message.contains('actual puzzle image') ||
        message.contains('generate the puzzle')) {
      return 'Generate the puzzle before submitting for review.';
    }
    if (message.contains('already been submitted') ||
        message.contains('now locked')) {
      return 'This level has already been submitted and is now locked.';
    }
    if (message.contains('remove profanity')) {
      return 'Please remove profanity before submitting for review.';
    }
    if (message.contains('could not be found')) {
      return 'Could not find this draft anymore. Please reopen My Levels and try again.';
    }
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

  String _friendlyDeleteError(Object error) {
    final message =
        error.toString().replaceFirst('Exception: ', '').toLowerCase();
    if (message.contains('signed in') ||
        message.contains('permission') ||
        message.contains('unauth') ||
        message.contains('forbidden')) {
      return 'Could not delete this draft right now. Please reopen Subliminal Words and try again.';
    }
    if (message.contains('locked')) {
      return 'Submitted levels cannot be deleted.';
    }
    if (message.contains('network') ||
        message.contains('connection') ||
        message.contains('timed out') ||
        message.contains('timeout') ||
        message.contains('temporarily unavailable') ||
        message.contains('service unavailable')) {
      return 'Could not delete this draft right now. Check your connection and try again.';
    }
    if (message.contains('puzzle generation')) {
      return 'Wait for puzzle generation to finish before deleting this level.';
    }
    return 'Could not delete this draft right now. Please try again.';
  }

  Future<void> _openEditor(BuildContext context, {SWLevel? level}) async {
    if (level == null) {
      await openCreateLevelFlow(context);
      return;
    }

    final latestLevel =
        await context.read<FirebaseService>().getMyLevel(level.documentId);
    if (!context.mounted) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<bool>(
        builder: (_) => CreateLevelScreen(initialLevel: latestLevel ?? level),
      ),
    );
  }

  Future<void> _playLevel(BuildContext context, SWLevel level) async {
    SWLevel levelToPlay = level;
    if (level.submissionStatus == UserLevelSubmissionStatus.approved &&
        level.submissionId != null &&
        level.submissionId!.contains('__')) {
      final parts = level.submissionId!.split('__');
      if (parts.length >= 2) {
        final packId = parts[0];
        final levelNr = int.tryParse(parts[1]) ?? 0;
        final liveLevel = await context.read<FirebaseService>().getLevel(packId, levelNr);
        if (liveLevel != null && liveLevel.id.isNotEmpty) {
          levelToPlay = liveLevel;
        }
      }
    }

    if (!context.mounted) {
      return;
    }

    await context.read<LevelModel>().loadLevelFromSelection(levelToPlay);
    if (context.mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  Future<void> _submitLevel(BuildContext context, SWLevel level) async {
    try {
      await context
          .read<FirebaseService>()
          .submitUserLevelForReview(level.documentId);
      showAppSnackBar('Level submitted for review.');
    } catch (error) {
      showAppSnackBar(_friendlySubmitError(error));
    }
  }

  Future<void> _deleteLevel(BuildContext context, SWLevel level) async {
    final isPublished =
        level.submissionStatus == UserLevelSubmissionStatus.approved;
    final removesAdminSubmission = !isPublished;
    final displayName = level.name.isEmpty ? 'Untitled Level' : level.name;
    final shouldDelete = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(isPublished ? 'Remove private copy?' : 'Delete draft?'),
            content: Text(
              isPublished
                  ? 'Remove "$displayName" from My Levels? The published live level will stay available to other players.'
                  : level.submissionStatus ==
                          UserLevelSubmissionStatus.pendingReview
                      ? 'Delete "$displayName" from My Levels and remove it from admin review too?'
                      : removesAdminSubmission
                          ? 'Delete "$displayName" from My Levels? Any pending or rejected submission history for this draft will also be removed from admin.'
                          : 'Delete "$displayName" from My Levels?',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;

    if (!shouldDelete || !context.mounted) {
      return;
    }

    try {
      final deleteMode = await context
          .read<FirebaseService>()
          .deleteMyLevel(level.documentId);
      if (!context.mounted) {
        return;
      }
      showAppSnackBar(
        deleteMode == 'private_copy_deleted'
            ? 'Removed from My Levels. The published live level stays available to players.'
            : 'Draft deleted.',
      );
    } catch (error) {
      showAppSnackBar(_friendlyDeleteError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final firebaseService = context.read<FirebaseService>();
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final adsController = context.watch<AdsController?>();
    final moneyController = context.watch<MoneyController?>();
    final needsAd = moneyController?.hasAllAccess() != true;

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
                        'Loading your levels',
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
              final isLevelBusy = _isLevelBusy(level.documentId);
              final statusLabel =
                  UserLevelSubmissionStatus.labelFor(level.submissionStatus);
              final hasPuzzleImage = level.hasReviewReadyPuzzleImage;
              final faceSourceSafetyStatus = (level.editorData[
                          'sourceImageSafetyStatus'] ??
                      level.editorData['sourceSafetyStatus'] ??
                      '')
                  .toString()
                  .trim()
                  .toLowerCase();
              final needsFaceSafetyResave =
                  level.editorMode == UserLevelEditorMode.photoSketch &&
                      faceSourceSafetyStatus != 'clean';
              final hasPendingPuzzleGeneration =
                  level.hasPendingPuzzleGeneration;
              final canSubmitForReview = hasPuzzleImage &&
                  level.hasRequiredFieldsForSubmission &&
                  !hasPendingPuzzleGeneration &&
                  !level.isLocked &&
                  !needsFaceSafetyResave &&
                  level.submissionStatus !=
                      UserLevelSubmissionStatus.pendingReview;

              final isApproved = level.submissionStatus == UserLevelSubmissionStatus.approved;
              final isPending = level.submissionStatus == UserLevelSubmissionStatus.pendingReview;
              final isRejected = level.submissionStatus == UserLevelSubmissionStatus.rejected;
              
              final badgeBgColor = isApproved ? Colors.green.withValues(alpha: 0.18) :
                                   isPending ? Colors.orange.withValues(alpha: 0.18) :
                                   isRejected ? colorScheme.errorContainer :
                                   colorScheme.secondaryContainer;
              final badgeFgColor = isApproved ? Colors.green.shade700 :
                                   isPending ? Colors.orange.shade800 :
                                   isRejected ? colorScheme.onErrorContainer :
                                   colorScheme.onSecondaryContainer;
              
              final canEdit = !level.isLocked && !hasPendingPuzzleGeneration && !isLevelBusy;

              return Card(
                elevation: 0,
                color: colorScheme.surfaceContainerHigh,
                surfaceTintColor: Colors.transparent,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: BorderSide(color: colorScheme.outlineVariant),
                ),
                child: InkWell(
                  onTap: canEdit
                      ? () => _runLevelAction(
                            level.documentId,
                            _LevelCardAction.edit,
                            () => _openEditor(context, level: level),
                          )
                      : (hasPuzzleImage && !isLevelBusy
                          ? () => _runLevelAction(
                                level.documentId,
                                _LevelCardAction.play,
                                () => _playLevel(context, level),
                              )
                          : null),
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
                              color: badgeBgColor,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              statusLabel,
                              style: textTheme.labelMedium?.copyWith(
                                color: badgeFgColor,
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
                          hasPendingPuzzleGeneration
                              ? 'Puzzle generation running'
                              : 'Generate a puzzle first',
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (hasPendingPuzzleGeneration) ...<Widget>[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.tertiaryContainer.withValues(
                              alpha: 0.72,
                            ),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: colorScheme.tertiary.withValues(alpha: 0.24),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.1,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    colorScheme.onTertiaryContainer,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  'Puzzle generation running',
                                  style: textTheme.labelLarge?.copyWith(
                                    color: colorScheme.onTertiaryContainer,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (needsFaceSafetyResave) ...<Widget>[
                        const SizedBox(height: 8),
                        Text(
                          'Open this photo level and save it again before submitting it for review.',
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (level.submissionStatus ==
                              UserLevelSubmissionStatus.rejected &&
                          level.submissionFeedback.trim().isNotEmpty) ...<Widget>[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: colorScheme.error.withValues(alpha: 0.18),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                'Review Feedback',
                                style: textTheme.labelLarge?.copyWith(
                                  color: colorScheme.onErrorContainer,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                level.submissionFeedback,
                                style: textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onErrorContainer,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      Row(
                        children: <Widget>[
                          _LevelActionIconButton(
                            tooltip: 'Play',
                            icon: needsAd
                                ? Icons.slideshow_rounded
                                : Icons.play_arrow_outlined,
                            enabled: hasPuzzleImage && !isLevelBusy,
                            isLoading: _isActionBusy(
                              level.documentId,
                              _LevelCardAction.play,
                            ),
                            onPressed: () => _runLevelAction(
                              level.documentId,
                              _LevelCardAction.play,
                              () => _playLevel(context, level),
                            ),
                            onUnavailable: () => _showActionBlocked(
                              context,
                              hasPuzzleImage
                                  ? 'Please wait for the current action to finish.'
                                  : hasPendingPuzzleGeneration
                                      ? 'This puzzle is still generating. Open the draft to resume it.'
                                      : 'Generate a puzzle first before playing this level.',
                            ),
                          ),
                          const SizedBox(width: 8),
                          _LevelActionIconButton(
                            tooltip: 'Edit',
                            icon: Icons.edit_outlined,
                            enabled: !level.isLocked && !hasPendingPuzzleGeneration && !isLevelBusy,
                            isLoading: _isActionBusy(
                              level.documentId,
                              _LevelCardAction.edit,
                            ),
                            onPressed: () => _runLevelAction(
                              level.documentId,
                              _LevelCardAction.edit,
                              () => _openEditor(context, level: level),
                            ),
                            onUnavailable: () => _showActionBlocked(
                              context,
                              level.isLocked
                                  ? 'Submitted levels are locked and can no longer be edited.'
                                  : hasPendingPuzzleGeneration
                                      ? 'Wait for puzzle generation to finish before editing.'
                                      : 'Please wait for the current action to finish.',
                            ),
                          ),
                          const SizedBox(width: 8),
                          _LevelActionIconButton(
                            tooltip: 'Submit for Review',
                            icon: Icons.publish_outlined,
                            enabled: canSubmitForReview && !isLevelBusy,
                            isLoading: _isActionBusy(
                              level.documentId,
                              _LevelCardAction.submit,
                            ),
                            onPressed: () => _runLevelAction(
                              level.documentId,
                              _LevelCardAction.submit,
                              () => _submitLevel(context, level),
                            ),
                            onUnavailable: () => _showActionBlocked(
                              context,
                              isLevelBusy
                                  ? 'Please wait for the current action to finish.'
                                  : !level.hasRequiredFieldsForSubmission
                                      ? 'Please complete all required fields (Creator, Hint, Solution, Puzzle) before submitting.'
                                      : !hasPuzzleImage
                                          ? 'Generate a puzzle first before submitting for review.'
                                      : hasPendingPuzzleGeneration
                                          ? 'Wait for puzzle generation to finish before submitting for review.'
                                      : needsFaceSafetyResave
                                          ? 'Open this photo level and save it again before submitting for review.'
                                          : 'This level is already submitted and waiting for review.',
                            ),
                            isPrimary: true,
                          ),
                          const SizedBox(width: 8),
                          _LevelActionIconButton(
                            tooltip: level.submissionStatus ==
                                    UserLevelSubmissionStatus.approved
                                ? 'Remove from My Levels'
                                : 'Delete Draft',
                            icon: Icons.delete_outline_rounded,
                            enabled:
                                !hasPendingPuzzleGeneration && !isLevelBusy,
                            isLoading: _isActionBusy(
                              level.documentId,
                              _LevelCardAction.delete,
                            ),
                            onPressed: () => _runLevelAction(
                              level.documentId,
                              _LevelCardAction.delete,
                              () => _deleteLevel(context, level),
                            ),
                            onUnavailable: () => _showActionBlocked(
                              context,
                              hasPendingPuzzleGeneration
                                  ? 'Open this draft and let puzzle generation finish before deleting it.'
                                  : 'Please wait for the current action to finish.',
                            ),
                            isDestructive: true,
                          ),
                        ],
                      ),
                    ],
                  ),
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

class _LevelActionIconButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final bool enabled;
  final bool isLoading;
  final VoidCallback onPressed;
  final VoidCallback? onUnavailable;
  final bool isPrimary;
  final bool isDestructive;

  const _LevelActionIconButton({
    required this.tooltip,
    required this.icon,
    required this.enabled,
    this.isLoading = false,
    required this.onPressed,
    this.onUnavailable,
    this.isPrimary = false,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final backgroundColor = isPrimary
        ? colorScheme.primaryContainer
        : isDestructive
            ? colorScheme.errorContainer.withValues(alpha: enabled ? 1 : 0.45)
            : colorScheme.surfaceContainerHighest;
    final foregroundColor = !enabled
        ? colorScheme.onSurfaceVariant.withValues(alpha: 0.38)
        : isPrimary
            ? colorScheme.onPrimaryContainer
            : isDestructive
                ? colorScheme.onErrorContainer
                : colorScheme.onSurface;
    final borderColor = isPrimary
        ? colorScheme.primary.withValues(alpha: 0.34)
        : isDestructive
            ? colorScheme.error.withValues(alpha: enabled ? 0.28 : 0.14)
            : colorScheme.outlineVariant;

    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: Semantics(
        button: true,
        enabled: enabled,
        label: tooltip,
          child: Material(
            color: backgroundColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: borderColor),
            ),
          child: InkWell(
            onTap: enabled ? onPressed : onUnavailable,
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 42,
              height: 42,
              child: Center(
                child: isLoading
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            foregroundColor,
                          ),
                        ),
                      )
                    : Icon(icon, size: 20, color: foregroundColor),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
