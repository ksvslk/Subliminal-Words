import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shimmer/shimmer.dart';
import 'package:logging/logging.dart';
import 'package:operation_hermes/controller/audio_controller.dart';
import 'package:operation_hermes/config/sounds.dart';
import 'package:operation_hermes/ui/confetti.dart';
import 'package:operation_hermes/change_notifier/field_model.dart';
import 'package:operation_hermes/ui/letter_box.dart';
import 'package:operation_hermes/data/letter_box_data.dart';
import 'package:operation_hermes/data/letter_box_state.dart';
import 'package:operation_hermes/change_notifier/level_model.dart';
import 'package:operation_hermes/controller/shimmer_placeholders.dart';
import 'package:operation_hermes/controller/games_services.dart';
import 'package:provider/provider.dart';

class GameField extends StatelessWidget {
  const GameField({super.key});
  static final _log = Logger('GameField');

  @override
  Widget build(BuildContext context) {
    final audioController = context.read<AudioController>();
    final gamesServices = context.read<GamesServicesController>();

    return Consumer<LevelModel>(
      builder: (context, levelModel, child) {
        // When loading, show the placeholder. This widget occupies the same space
        // as the real content, preventing layout shifts.
        if (levelModel.networkRequestActive) {
          return const GameFieldPlaceholder();
        }

        // When ready, show the actual game field content.
        return Stack(
          children: [
            ChangeNotifierProvider<FieldModel>.value(
              value: levelModel.fieldModel,
              child: const _GameGrid(),
            ),
            Confetti(
                startConfetti:
                    levelModel.levelNr == 200 && levelModel.levelCompleted),
          ],
        );
      },
    );
  }
}

class _GameGrid extends StatelessWidget {
  const _GameGrid();

  @override
  Widget build(BuildContext context) {
    final fieldModel = context.watch<FieldModel>();
    if (fieldModel.word.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        const Flexible(child: FractionallySizedBox(heightFactor: 0.5)),
        const Flexible(
          flex: 10,
          child: _SolutionRow(),
        ),
        const Flexible(child: FractionallySizedBox(heightFactor: 0.5)),
        for (var i = 0; i < 2; i++)
          Flexible(
            flex: 10,
            child: _FieldRow(rowIndex: i),
          ),
      ],
    );
  }
}

class _SolutionRow extends StatelessWidget {
  const _SolutionRow();

  @override
  Widget build(BuildContext context) {
    final fieldModel = context.watch<FieldModel>();
    final levelModel = context.watch<LevelModel>();
    final audioController = context.read<AudioController>();

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final (i, letterData) in fieldModel.solution.indexed)
          Flexible(
            child: _LetterBoxWrapper(
              // Pass the LetterBoxData directly to the onTap callback
              onTap: (currentData) {
                // currentData is now the specific LetterBoxData for this LetterBox
                if (currentData.state == LetterBoxState.solutionPick &&
                    !levelModel.levelCompleted) {
                  audioController.playSfx(SfxType.freeLetter);
                  fieldModel.removeLetter(i);
                }
              },
              child: LetterBox(
                key: ValueKey('solution-$i'),
                data: letterData,
              ),
            ),
          ),
      ],
    );
  }
}

class _FieldRow extends StatelessWidget {
  final int rowIndex;
  const _FieldRow({required this.rowIndex});

  @override
  Widget build(BuildContext context) {
    final fieldModel = context.watch<FieldModel>();
    final levelModel = context.watch<LevelModel>();
    final audioController = context.read<AudioController>();
    final gamesServices = context.read<GamesServicesController>();

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(7, (columnIndex) {
        final index = rowIndex * 7 + columnIndex;
        if (index >= fieldModel.field.length) {
          return const Flexible(child: AspectRatio(aspectRatio: 1));
        }
        final letterData = fieldModel.field[index];

        return Flexible(
          child: _LetterBoxWrapper(
            onTap: (currentData) {
              // Pass the LetterBoxData directly to the onTap callback // Corrected signature to accept LetterBoxData
              if (!levelModel.levelCompleted &&
                  currentData.state == LetterBoxState.fieldPick &&
                  !fieldModel.isLastLetter()) {
                HapticFeedback.selectionClick();
                audioController.playSfx(SfxType.pickLetter);
                fieldModel.putLetter(index);
                if (levelModel.checkForWin()) {
                  HapticFeedback.mediumImpact();
                  audioController.playSfx(SfxType.win);
                }
              }
            },
            child: LetterBox(data: letterData),
          ),
        );
      }),
    );
  }
}

class _LetterBoxWrapper extends StatelessWidget {
  final Function(LetterBoxData) onTap; // Changed to accept LetterBoxData
  final Widget child;

  const _LetterBoxWrapper({
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      // The child is a LetterBox which needs the data, so we find it from the parent.
      value: (child as LetterBox).data,
      child: Consumer<LetterBoxData>(
        builder: (context, data, _) {
          return GestureDetector( // The onTap here will now pass 'data'
            onTap: () => onTap(data),
            child: AspectRatio(
              aspectRatio: 1,
              child: child,
            ),
          );
        },
      ),
    );
  }
}
