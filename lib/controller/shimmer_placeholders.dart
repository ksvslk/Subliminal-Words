import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

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
          const Spacer(flex: 1),
          Expanded(
            flex: 10,
            child: _buildShimmerRow(7),
          ),
          const Spacer(flex: 1),
          ...List.generate(2, (rowIndex) {
            return Expanded(
              flex: 10,
              child: _buildShimmerRow(7),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildShimmerRow(int count) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (_) {
        return Expanded(
          child: Center(
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
          ),
        );
      }),
    );
  }
}

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