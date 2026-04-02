import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:operation_hermes/ui/freud_dialog.dart';
import 'package:operation_hermes/ui/game_field.dart';
import 'package:operation_hermes/ui/hint_bar.dart';
import 'package:operation_hermes/change_notifier/level_model.dart';
import 'package:operation_hermes/ui/create_level_flow.dart';
import 'package:operation_hermes/ui/puzzle.dart';
import 'package:operation_hermes/menu/top_bar.dart';
import 'package:operation_hermes/ui/random_tutorial_overlay.dart';
import 'package:provider/provider.dart';

class GameFieldScreen extends StatefulWidget {
  const GameFieldScreen({super.key});

  @override
  State<GameFieldScreen> createState() => _GameFieldScreenState();
}

class _GameFieldScreenState extends State<GameFieldScreen> {
  bool _isInitializing = true;

  // 1. Define keys here (local to this screen only)
  final GlobalKey _stackKey = GlobalKey();
  final GlobalKey _clueAreaKey = GlobalKey();
  final GlobalKey _playZoneKey = GlobalKey();
  Rect? _creatorOverlayRect;

  void _syncCreatorOverlayRect() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final stackContext = _stackKey.currentContext;
      final clueContext = _clueAreaKey.currentContext;
      if (stackContext == null || clueContext == null) {
        return;
      }
      final stackBox = stackContext.findRenderObject() as RenderBox?;
      final clueBox = clueContext.findRenderObject() as RenderBox?;
      if (stackBox == null || clueBox == null) {
        return;
      }

      final topLeft = clueBox.localToGlobal(
        Offset.zero,
        ancestor: stackBox,
      );
      final nextRect = topLeft & clueBox.size;
      final currentRect = _creatorOverlayRect;
      if (currentRect != null &&
          (currentRect.left - nextRect.left).abs() < 0.5 &&
          (currentRect.top - nextRect.top).abs() < 0.5 &&
          (currentRect.width - nextRect.width).abs() < 0.5 &&
          (currentRect.height - nextRect.height).abs() < 0.5) {
        return;
      }
      setState(() {
        _creatorOverlayRect = nextRect;
      });
    });
  }

  @override
  void initState() {
    super.initState();
    context.read<LevelModel>().initialize().then((_) {
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return const Center(child: CircularProgressIndicator());
    }

    return Consumer<LevelModel>(
      builder: (context, levelModel, child) {
        final creatorName = (levelModel.currentLevel?.creatorName ?? '').trim();
        _syncCreatorOverlayRect();

        // 2. Determine which text to show
        // You might need a check here like: levelModel.isMovieLevel
        String hintText = "Do You see the word?";

        return SafeArea(
          child: Stack(
            key: _stackKey,
            children: [
              // 3. Wrap the content in the Tutorial Overlay
              RandomTutorialOverlay(
                tutorialId: 'tutorial_intro_v1',
                hintText: hintText,
                clueKey: _clueAreaKey, // Target for Step 1
                playZoneKey: _playZoneKey, // Target for Step 2
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Flexible(flex: 1, child: TopBar()),
                        // 4. Wrap Puzzle in a Container with the key
                        // We do NOT modify the Puzzle widget itself.
                        Flexible(
                          flex: 8,
                          child: Container(
                            key: _clueAreaKey,
                            child: const Puzzle(),
                          ),
                        ),
                        Flexible(
                          flex: 3,
                          child: AnimatedOpacity(
                            opacity: levelModel.isLevelReady ? 1.0 : 0.0,
                            duration: const Duration(milliseconds: 400),
                            child: Container(
                              key: _playZoneKey,
                              child: const GameField(),
                            ),
                          ),
                        ),
                        Flexible(
                          flex: 1,
                          child: HintBar(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (creatorName.isNotEmpty && _creatorOverlayRect != null)
                Positioned(
                  left: _creatorOverlayRect!.left + 12,
                  top: _creatorOverlayRect!.top + 12,
                  child: _CreatorCreditOverlay(
                    creatorName: creatorName,
                    onTap: () => openCreateLevelFlow(context),
                  ),
                ),
              const FreudDialog(),
            ],
          ),
        );
      },
    );
  }
}

class _CreatorCreditOverlay extends StatelessWidget {
  const _CreatorCreditOverlay({
    required this.creatorName,
    required this.onTap,
  });

  final String creatorName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    colorScheme.surface.withValues(alpha: 0.30),
                    colorScheme.surfaceContainerHigh.withValues(alpha: 0.18),
                  ],
                ),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: colorScheme.outline.withValues(alpha: 0.10),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.person_outline,
                      size: 14,
                      color: colorScheme.onSurface.withValues(alpha: 0.56),
                    ),
                    const SizedBox(width: 6),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.sizeOf(context).width * 0.40,
                      ),
                      child: Text(
                        creatorName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.labelMedium?.copyWith(
                          color: colorScheme.onSurface.withValues(alpha: 0.66),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.add_circle_outline,
                      size: 14,
                      color: colorScheme.onSurface.withValues(alpha: 0.44),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
