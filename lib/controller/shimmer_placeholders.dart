import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// A shimmer placeholder that mimics the layout of the hint buttons.
class ActionButtonsPlaceholder extends StatelessWidget {
  const ActionButtonsPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Shimmer.fromColors(
      baseColor: colorScheme.surface,
      highlightColor: colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(3, (_) {
            return const CircleAvatar(
              radius: 28,
              backgroundColor: Colors.white,
            );
          }),
        ),
      ),
    );
  }
}

/// A shimmer placeholder that mimics the layout of the letter input fields.
class GameFieldPlaceholder extends StatelessWidget {
  const GameFieldPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Shimmer.fromColors(
      baseColor: colorScheme.surface,
      highlightColor: colorScheme.surfaceContainerHighest,
      child: Column(
        children: [
          const Flexible(child: FractionallySizedBox(heightFactor: 0.5)),
          // Mimics the solution row
          Flexible(
            flex: 10,
            child: _buildShimmerRow(7), // Average solution length
          ),
          const Flexible(child: FractionallySizedBox(heightFactor: 0.5)),
          // Mimics the two rows of selectable letters
          ...List.generate(2, (rowIndex) {
            return Flexible(
              flex: 10,
              child: _buildShimmerRow(7), // Field rows always have 7 letters
            );
          }),
        ],
      ),
    );
  }

  /// Builds a single shimmering row of boxes to represent letter fields.
  Widget _buildShimmerRow(int count) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (_) {
        return Flexible(
          child: AspectRatio(
            aspectRatio: 1,
            child: Padding(
              padding: const EdgeInsets.all(2.0),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

/// A shimmer placeholder that mimics a single level button in the level grid.
class LevelButtonPlaceholder extends StatelessWidget {
  const LevelButtonPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Shimmer.fromColors(
      baseColor: colorScheme.surface,
      highlightColor: colorScheme.surfaceContainerHighest,
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }
}