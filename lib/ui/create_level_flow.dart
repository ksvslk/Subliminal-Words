import 'package:flutter/material.dart';
import 'package:operation_hermes/controller/firebase_service.dart';
import 'package:operation_hermes/data/user_level_metadata.dart';
import 'package:operation_hermes/ui/app_scaffold_messenger.dart';
import 'package:operation_hermes/ui/screen/create_level_screen.dart';
import 'package:provider/provider.dart';

Future<void> openCreateLevelFlow(BuildContext context) async {
  final firebaseService = context.read<FirebaseService>();
  try {
    await firebaseService.assertUserCanCreateLevels();
  } catch (_) {
    showAppSnackBar('Level creation is unavailable for this account right now.');
    return;
  }

  if (!context.mounted) {
    return;
  }

  final selectedMode = await showDialog<String>(
    context: context,
    builder: (_) => const _CreateLevelTypeDialog(),
  );

  if (!context.mounted || selectedMode == null) {
    return;
  }

  await Navigator.of(context).push(
    MaterialPageRoute<bool>(
      builder: (_) => CreateLevelScreen(initialEditorMode: selectedMode),
    ),
  );
}

class _CreateLevelTypeDialog extends StatelessWidget {
  const _CreateLevelTypeDialog();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Create Level',
                    style: textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Close',
                ),
              ],
            ),
            Text(
              'What kind of level do you want to make?',
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            _CreateLevelTypeOption(
              icon: Icons.face_retouching_natural_outlined,
              title: 'Face',
              subtitle: 'Upload a face photo, shape the sketch, then generate the puzzle.',
              enabled: true,
              colorScheme: colorScheme,
              onTap: () => Navigator.of(context).pop(
                UserLevelEditorMode.photoSketch,
              ),
            ),
            const SizedBox(height: 12),
            _CreateLevelTypeOption(
              icon: Icons.draw_outlined,
              title: 'Object',
              subtitle: 'Draw the solution, then generate the puzzle.',
              enabled: true,
              colorScheme: colorScheme,
              onTap: () => Navigator.of(context).pop(
                UserLevelEditorMode.drawObject,
              ),
            ),
            const SizedBox(height: 12),
            _CreateLevelTypeOption(
              icon: Icons.text_fields_outlined,
              title: 'Word',
              subtitle: 'Arrange letters on the stage, then generate the puzzle.',
              enabled: true,
              colorScheme: colorScheme,
              onTap: () => Navigator.of(context).pop(
                UserLevelEditorMode.highlight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateLevelTypeOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final ColorScheme colorScheme;
  final VoidCallback? onTap;

  const _CreateLevelTypeOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.colorScheme,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final foregroundColor =
        enabled ? colorScheme.onSurface : colorScheme.onSurfaceVariant;
    final backgroundColor = enabled
        ? colorScheme.surfaceContainerLow
        : colorScheme.surfaceContainerLowest;

    return Opacity(
      opacity: enabled ? 1 : 0.72,
      child: Material(
        color: backgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(
            color: enabled
                ? colorScheme.outlineVariant
                : colorScheme.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Row(
              children: <Widget>[
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: enabled
                        ? colorScheme.primaryContainer
                        : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    icon,
                    color: enabled
                        ? colorScheme.onPrimaryContainer
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              title,
                              style: textTheme.titleMedium?.copyWith(
                                color: foregroundColor,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          if (!enabled)
                            Text(
                              'Soon',
                              style: textTheme.labelMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (enabled) ...<Widget>[
                  const SizedBox(width: 10),
                  Icon(
                    Icons.arrow_forward_rounded,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
