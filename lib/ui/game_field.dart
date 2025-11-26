import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:operation_hermes/controller/audio_controller.dart';
import 'package:operation_hermes/config/sounds.dart';
import 'package:operation_hermes/change_notifier/field_model.dart';
import 'package:operation_hermes/ui/letter_box.dart';
import 'package:operation_hermes/data/letter_box_data.dart';
import 'package:operation_hermes/data/letter_box_state.dart';
import 'package:operation_hermes/change_notifier/level_model.dart';
import 'package:operation_hermes/controller/shimmer_placeholders.dart';
import 'package:provider/provider.dart';

class GameField extends StatelessWidget {
  const GameField({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<LevelModel>(
      builder: (context, levelModel, child) {
        if (levelModel.networkRequestActive) {
          return const GameFieldPlaceholder();
        }
        return Stack(
          children: [
            ChangeNotifierProvider<FieldModel>.value(
              value: levelModel.fieldModel,
              child: const _GameGrid(),
            ),
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
              onTap: (currentData) {
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
  final Function(LetterBoxData) onTap;
  final Widget child;

  const _LetterBoxWrapper({
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: (child as LetterBox).data,
      child: Consumer<LetterBoxData>(
        builder: (context, data, _) {
          return GestureDetector(
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
