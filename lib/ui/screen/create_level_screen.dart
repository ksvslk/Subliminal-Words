import 'dart:typed_data';

import 'package:auto_size_text/auto_size_text.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:operation_hermes/controller/firebase_service.dart';
import 'package:operation_hermes/data/sw_level.dart';
import 'package:operation_hermes/editor/content_filter.dart';
import 'package:operation_hermes/editor/drawing_canvas.dart';
import 'package:provider/provider.dart';

enum _StagePreviewMode {
  solution,
  puzzle,
}

DrawingBrushType _brushFromName(String? name) {
  return DrawingBrushType.values.firstWhere(
    (brush) => brush.name == name,
    orElse: () => DrawingBrushType.pencil,
  );
}

class CreateLevelScreen extends StatefulWidget {
  final SWLevel? initialLevel;

  const CreateLevelScreen({super.key, this.initialLevel});

  @override
  State<CreateLevelScreen> createState() => _CreateLevelScreenState();
}

class _CreateLevelScreenState extends State<CreateLevelScreen> {
  static const Color _generationExportBackground = Colors.white;

  late final TextEditingController _creatorNameController;
  late final TextEditingController _answerController;
  late final TextEditingController _factController;
  late final TextEditingController _generationPromptController;
  late final DrawingController _drawingController;
  late final Future<String>? _existingPuzzlePreviewUrlFuture;

  bool _isSaving = false;
  bool _isGeneratingPuzzle = false;
  bool _isStageInteracting = false;
  double _generationDifficulty = 1.5;
  String _puzzleGenerationStatus = '';
  Uint8List? _generatedPuzzleImageBytes;
  _StagePreviewMode _stagePreviewMode = _StagePreviewMode.solution;
  bool _hasPuzzleInvalidatedByEdit = false;
  int _lastSeenContentVersion = 0;

  bool get _isLocked => widget.initialLevel?.isLocked == true;
  bool get _isEditMode => widget.initialLevel != null;
  bool get _hasStoredPuzzleImage =>
      widget.initialLevel?.hasReviewReadyPuzzleImage == true &&
      !_hasPuzzleInvalidatedByEdit;
  bool get _hasPuzzleImageForReview =>
      _generatedPuzzleImageBytes != null || _hasStoredPuzzleImage;
  bool get _canSubmitForReview => _validateInputs(forSubmission: true) == null;

  @override
  void initState() {
    super.initState();
    final initialLevel = widget.initialLevel;
    final initialEditorData =
        initialLevel?.editorData ?? const <String, dynamic>{};

    _creatorNameController =
        TextEditingController(text: initialLevel?.creatorName ?? '');
    _answerController = TextEditingController(text: initialLevel?.name ?? '');
    _factController = TextEditingController(text: initialLevel?.factHint ?? '');
    _generationPromptController = TextEditingController(
      text: initialEditorData['generationPrompt'] as String? ??
          initialLevel?.name ??
          '',
    );
    _generationDifficulty =
        (initialEditorData['generationDifficulty'] as num?)?.toDouble() ?? 1.5;

    final initialStrokes = <DrawingStroke>[];
    final strokeJson = initialLevel?.editorData['strokes'] as List<dynamic>? ??
        const <dynamic>[];
    for (final stroke in strokeJson) {
      if (stroke is Map) {
        initialStrokes
            .add(DrawingStroke.fromJson(Map<String, dynamic>.from(stroke)));
      }
    }

    final brushSettings =
        initialEditorData['brushSettings'] as Map<dynamic, dynamic>? ??
            const <dynamic, dynamic>{};
    final initialBrushWidths = <DrawingBrushType, double>{};
    final initialBrushOpacities = <DrawingBrushType, double>{};

    for (final brush in DrawingBrushType.values) {
      final rawSettings = brushSettings[brush.name];
      if (rawSettings is! Map) {
        continue;
      }
      final settingsMap = Map<String, dynamic>.from(rawSettings);
      final width = settingsMap['width'];
      final opacity = settingsMap['opacity'];
      if (width is num) {
        initialBrushWidths[brush] = width.toDouble();
      }
      if (opacity is num) {
        initialBrushOpacities[brush] = opacity.toDouble();
      }
    }

    _drawingController = DrawingController(
      initialStrokes: initialStrokes,
      initialBrush:
          _brushFromName(initialEditorData['selectedBrush'] as String?),
      initialBrushWidths: initialBrushWidths,
      initialBrushOpacities: initialBrushOpacities,
    );
    _lastSeenContentVersion = _drawingController.contentVersion;
    _drawingController.addListener(_handleDrawingControllerChanged);
    _answerController.addListener(_handleGenerationInputsChanged);
    _factController.addListener(_handleGenerationInputsChanged);
    _generationPromptController.addListener(_handleGenerationInputsChanged);
    _existingPuzzlePreviewUrlFuture = _hasStoredPuzzleImage
        ? context
            .read<FirebaseService>()
            .getDownloadUrl(initialLevel!.puzzlePath)
        : null;
  }

  @override
  void dispose() {
    _creatorNameController.dispose();
    _answerController.dispose();
    _factController.dispose();
    _generationPromptController.dispose();
    _drawingController.removeListener(_handleDrawingControllerChanged);
    _answerController.removeListener(_handleGenerationInputsChanged);
    _factController.removeListener(_handleGenerationInputsChanged);
    _generationPromptController.removeListener(_handleGenerationInputsChanged);
    _drawingController.dispose();
    super.dispose();
  }

  Color _canvasBackgroundColor(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    if (theme.brightness == Brightness.dark) {
      return colorScheme.inverseSurface;
    }

    return colorScheme.surfaceContainerLowest;
  }

  void _handleDrawingControllerChanged() {
    final contentVersion = _drawingController.contentVersion;
    if (contentVersion == _lastSeenContentVersion) {
      return;
    }

    _lastSeenContentVersion = contentVersion;
    _invalidatePuzzlePreview();
  }

  void _handleGenerationInputsChanged() {
    _invalidatePuzzlePreview();
  }

  void _invalidatePuzzlePreview() {
    if (_generatedPuzzleImageBytes == null && !_hasStoredPuzzleImage) {
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _generatedPuzzleImageBytes = null;
      _hasPuzzleInvalidatedByEdit = true;
      _stagePreviewMode = _StagePreviewMode.solution;
      if (!_isGeneratingPuzzle) {
        _puzzleGenerationStatus = '';
      }
    });
  }

  String _resolvedGenerationPrompt() {
    final manualPrompt = _generationPromptController.text.trim();
    if (manualPrompt.isNotEmpty) {
      return manualPrompt;
    }

    final answer = _answerController.text.trim();
    final factHint = _factController.text.trim();
    if (answer.isEmpty && factHint.isEmpty) {
      return '';
    }

    if (answer.isNotEmpty && factHint.isNotEmpty) {
      return '$answer. $factHint';
    }

    return answer.isNotEmpty ? answer : factHint;
  }

  Future<void> _generatePuzzle() async {
    if (_isLocked || _isGeneratingPuzzle) {
      return;
    }

    final prompt = _resolvedGenerationPrompt();
    if (prompt.isEmpty) {
      _showSnack('Add a scene prompt or object details before generating.');
      return;
    }

    for (final value in <String>[prompt]) {
      if (ContentFilter.containsBlockedTerm(value)) {
        _showSnack('Please remove profanity before generating.');
        return;
      }
    }

    FocusScope.of(context).unfocus();
    final firebaseService = context.read<FirebaseService>();

    setState(() {
      _isGeneratingPuzzle = true;
      _puzzleGenerationStatus = 'Preparing solution image...';
      _stagePreviewMode = _StagePreviewMode.puzzle;
    });

    try {
      final solutionBytes = await exportDrawingAsPng(
        strokes: _drawingController.strokes,
        backgroundColor: _generationExportBackground,
      );

      final puzzleBytes = await firebaseService.generateDrawObjectPuzzle(
        solutionPngBytes: solutionBytes,
        prompt: prompt,
        difficulty: _generationDifficulty,
        onStatusChanged: (status) {
          if (!mounted) {
            return;
          }
          setState(() => _puzzleGenerationStatus = status);
        },
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _generatedPuzzleImageBytes = puzzleBytes;
        _hasPuzzleInvalidatedByEdit = false;
        _stagePreviewMode = _StagePreviewMode.puzzle;
        _puzzleGenerationStatus = 'Puzzle ready';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _stagePreviewMode = _StagePreviewMode.solution;
        _puzzleGenerationStatus = '';
      });
      _showSnack(
        error
            .toString()
            .replaceFirst('Exception: ', '')
            .replaceFirst('Bad state: ', ''),
      );
    } finally {
      if (mounted) {
        setState(() => _isGeneratingPuzzle = false);
      }
    }
  }

  String? _validateInputs({required bool forSubmission}) {
    final creatorName = _creatorNameController.text.trim();
    final answer = _answerController.text.trim();
    final factHint = _factController.text.trim();

    if (creatorName.isEmpty) {
      return 'Add a public creator name before saving.';
    }
    if (answer.length < 2) {
      return 'Name the object with at least 2 characters.';
    }
    if (factHint.isEmpty) {
      return 'Add a fact hint before saving.';
    }
    if (!_drawingController.hasCommittedStrokes) {
      return 'Draw something before saving.';
    }
    if (forSubmission && !_hasPuzzleImageForReview) {
      return 'Generate the puzzle before submitting for review.';
    }

    for (final value in <String>[creatorName, answer, factHint]) {
      if (ContentFilter.containsBlockedTerm(value)) {
        return 'Please remove profanity before saving.';
      }
    }

    return null;
  }

  Future<void> _save({required bool submitAfterSave}) async {
    final validationMessage =
        _validateInputs(forSubmission: submitAfterSave);
    if (validationMessage != null) {
      _showSnack(validationMessage);
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isSaving = true);
    final firebaseService = context.read<FirebaseService>();

    try {
      final pngBytes = await exportDrawingAsPng(
        strokes: _drawingController.strokes,
        backgroundColor: _generationExportBackground,
      );
      final editorData = _drawingController.toEditorData()
        ..['generationPrompt'] = _generationPromptController.text.trim()
        ..['generationDifficulty'] = _generationDifficulty;

      final levelId = await firebaseService.saveDrawObjectLevel(
        levelId: widget.initialLevel?.documentId,
        creatorName: _creatorNameController.text,
        answer: _answerController.text,
        factText: _factController.text,
        solutionPngBytes: pngBytes,
        puzzleImageBytes: _generatedPuzzleImageBytes,
        allowReuseExistingPuzzle: !_hasPuzzleInvalidatedByEdit,
        editorData: editorData,
      );

      if (submitAfterSave) {
        await firebaseService.submitUserLevelForReview(levelId);
      }

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(true);
    } catch (error) {
      _showSnack(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _handleStageInteractionChanged(bool isInteracting) {
    if (_isStageInteracting == isInteracting || !mounted) {
      return;
    }

    setState(() => _isStageInteracting = isInteracting);
  }

  Offset _normalizePoint(Offset localPosition, Size size) {
    final normalizedX = (localPosition.dx / size.width).clamp(0.0, 1.0);
    final normalizedY = (localPosition.dy / size.height).clamp(0.0, 1.0);
    return Offset(normalizedX, normalizedY);
  }

  InputDecoration _fieldDecoration(
    ColorScheme colorScheme, {
    required String label,
    IconData? icon,
  }) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide(color: colorScheme.outlineVariant),
    );

    return InputDecoration(
      labelText: label,
      prefixIcon: icon == null ? null : Icon(icon),
      filled: true,
      fillColor: colorScheme.surfaceContainerHigh,
      border: border,
      enabledBorder: border,
      disabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(color: colorScheme.primary, width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final canvasBackgroundColor = _canvasBackgroundColor(theme);
    final editorTheme = theme.copyWith(
      scaffoldBackgroundColor: colorScheme.surface,
      appBarTheme: theme.appBarTheme.copyWith(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: Colors.transparent,
      ),
    );

    return Theme(
      data: editorTheme,
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        appBar: AppBar(
          backgroundColor: colorScheme.surface,
          foregroundColor: colorScheme.onSurface,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          title: Text(_isEditMode ? 'Edit Level' : 'Create Level'),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.surface,
              border: Border(
                top: BorderSide(color: colorScheme.outlineVariant),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: AnimatedBuilder(
                animation: Listenable.merge(<Listenable>[
                  _creatorNameController,
                  _answerController,
                  _factController,
                  _drawingController,
                ]),
                builder: (context, _) => Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isSaving || _isLocked
                            ? null
                            : () => _save(submitAfterSave: false),
                        child: Text(_isSaving ? 'Saving...' : 'Save Draft'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _isSaving || _isLocked || !_canSubmitForReview
                            ? null
                            : () => _save(submitAfterSave: true),
                        child: Text(
                          _isSaving ? 'Submitting...' : 'Submit for Review',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        body: SafeArea(
          top: false,
          child: SingleChildScrollView(
            physics: _isStageInteracting
                ? const NeverScrollableScrollPhysics()
                : const ClampingScrollPhysics(),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                AutoSizeText(
                  'Choose a creator mode',
                  maxLines: 1,
                  minFontSize: 12,
                  style: textTheme.titleMedium?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                AutoSizeText(
                  'Object is live now. Face and Word come next.',
                  maxLines: 1,
                  minFontSize: 11,
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: const <Widget>[
                    _ModePill(
                      label: 'Face',
                      icon: Icons.face_retouching_natural_outlined,
                      selected: false,
                      enabled: false,
                    ),
                    _ModePill(
                      label: 'Object',
                      icon: Icons.draw_outlined,
                      selected: true,
                      enabled: true,
                    ),
                    _ModePill(
                      label: 'Word',
                      icon: Icons.text_fields_outlined,
                      selected: false,
                      enabled: false,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _SectionCard(
                  child: _CanvasEditorSection(
                    controller: _drawingController,
                    promptController: _generationPromptController,
                    textTheme: textTheme,
                    colorScheme: colorScheme,
                    canvasBackgroundColor: canvasBackgroundColor,
                    isLocked: _isLocked,
                    stagePreviewMode: _stagePreviewMode,
                    puzzleBytes: _generatedPuzzleImageBytes,
                    existingPuzzlePreviewUrlFuture: _existingPuzzlePreviewUrlFuture,
                    hasStoredPuzzleImage: _hasStoredPuzzleImage,
                    isGeneratingPuzzle: _isGeneratingPuzzle,
                    puzzleGenerationStatus: _puzzleGenerationStatus,
                    generationDifficulty: _generationDifficulty,
                    normalizePoint: _normalizePoint,
                    onStageInteractionChanged: _handleStageInteractionChanged,
                    onSelectStagePreview: (mode) =>
                        setState(() => _stagePreviewMode = mode),
                    onGeneratePuzzle: _generatePuzzle,
                    onGenerationDifficultyChanged: (value) => setState(
                      () => _generationDifficulty = value,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      TextField(
                        controller: _creatorNameController,
                        enabled: !_isLocked,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        decoration: _fieldDecoration(
                          colorScheme,
                          label: 'Creator Name',
                          icon: Icons.badge_outlined,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _answerController,
                        enabled: !_isLocked,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        decoration: _fieldDecoration(
                          colorScheme,
                          label: 'Object Name',
                          icon: Icons.extension_outlined,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _factController,
                        enabled: !_isLocked,
                        maxLines: 2,
                        decoration: _fieldDecoration(
                          colorScheme,
                          label: 'Fact Hint',
                          icon: Icons.lightbulb_outline,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_isLocked) ...<Widget>[
                  const SizedBox(height: 16),
                  _LockedNotice(colorScheme: colorScheme),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CanvasEditorSection extends StatelessWidget {
  final DrawingController controller;
  final TextEditingController promptController;
  final TextTheme textTheme;
  final ColorScheme colorScheme;
  final Color canvasBackgroundColor;
  final bool isLocked;
  final _StagePreviewMode stagePreviewMode;
  final Uint8List? puzzleBytes;
  final Future<String>? existingPuzzlePreviewUrlFuture;
  final bool hasStoredPuzzleImage;
  final bool isGeneratingPuzzle;
  final String puzzleGenerationStatus;
  final double generationDifficulty;
  final Offset Function(Offset localPosition, Size size) normalizePoint;
  final ValueChanged<bool> onStageInteractionChanged;
  final ValueChanged<_StagePreviewMode> onSelectStagePreview;
  final VoidCallback onGeneratePuzzle;
  final ValueChanged<double> onGenerationDifficultyChanged;

  const _CanvasEditorSection({
    required this.controller,
    required this.promptController,
    required this.textTheme,
    required this.colorScheme,
    required this.canvasBackgroundColor,
    required this.isLocked,
    required this.stagePreviewMode,
    required this.puzzleBytes,
    required this.existingPuzzlePreviewUrlFuture,
    required this.hasStoredPuzzleImage,
    required this.isGeneratingPuzzle,
    required this.puzzleGenerationStatus,
    required this.generationDifficulty,
    required this.normalizePoint,
    required this.onStageInteractionChanged,
    required this.onSelectStagePreview,
    required this.onGeneratePuzzle,
    required this.onGenerationDifficultyChanged,
  });

  @override
  Widget build(BuildContext context) {
    final hasPuzzlePreview = puzzleBytes != null || hasStoredPuzzleImage;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: AutoSizeText(
                stagePreviewMode == _StagePreviewMode.solution
                    ? 'Draw the solution'
                    : 'Preview the generated puzzle',
                maxLines: 1,
                minFontSize: 12,
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
            const SizedBox(width: 12),
            SegmentedButton<_StagePreviewMode>(
              segments: const <ButtonSegment<_StagePreviewMode>>[
                ButtonSegment<_StagePreviewMode>(
                  value: _StagePreviewMode.solution,
                  label: Text('Solution'),
                ),
                ButtonSegment<_StagePreviewMode>(
                  value: _StagePreviewMode.puzzle,
                  label: Text('Puzzle'),
                ),
              ],
              selected: <_StagePreviewMode>{stagePreviewMode},
              showSelectedIcon: false,
              onSelectionChanged: isLocked
                  ? null
                  : (selection) => onSelectStagePreview(selection.first),
            ),
          ],
        ),
        const SizedBox(height: 12),
        AspectRatio(
          aspectRatio: 1,
          child: stagePreviewMode == _StagePreviewMode.solution
              ? _DrawingStage(
                  controller: controller,
                  backgroundColor: canvasBackgroundColor,
                  borderColor: colorScheme.outlineVariant,
                  isLocked: isLocked,
                  normalizePoint: normalizePoint,
                  onInteractionChanged: onStageInteractionChanged,
                )
              : _PuzzleStage(
                  puzzleBytes: puzzleBytes,
                  existingPreviewUrlFuture: existingPuzzlePreviewUrlFuture,
                  hasStoredPuzzleImage: hasStoredPuzzleImage,
                  isGeneratingPuzzle: isGeneratingPuzzle,
                  statusText: puzzleGenerationStatus,
                  borderColor: colorScheme.outlineVariant,
                  backgroundColor: canvasBackgroundColor,
                  foregroundColor: colorScheme.onSurfaceVariant,
                ),
        ),
        const SizedBox(height: 12),
        if (stagePreviewMode == _StagePreviewMode.solution) ...<Widget>[
          Text(
            'Tools',
            style: textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              final hasStrokes = controller.hasCommittedStrokes;
              final selectedBrush = controller.selectedBrush;
              final currentOpacity = controller.currentOpacity;
              final currentWidth = controller.currentWidth;
              final canAdjustOpacity = selectedBrush != DrawingBrushType.eraser;

              return Column(
                children: <Widget>[
                  SizedBox(
                    height: 56,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: DrawingBrushType.values.length,
                      padding: EdgeInsets.zero,
                      itemBuilder: (context, index) {
                        final brush = DrawingBrushType.values[index];
                        return _BrushButton(
                          brush: brush,
                          selected: selectedBrush == brush,
                          enabled: !isLocked,
                          onTap: () => controller.selectBrush(brush),
                        );
                      },
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      SizedBox(
                        width: 64,
                        child: AutoSizeText(
                          canAdjustOpacity ? 'Opacity' : 'Eraser',
                          maxLines: 1,
                          minFontSize: 10,
                          style: textTheme.labelMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Opacity(
                          opacity: canAdjustOpacity ? 1 : 0.45,
                          child: Slider(
                            value: currentOpacity,
                            min: 0.2,
                            max: 1.0,
                            divisions: 8,
                            onChanged:
                                canAdjustOpacity ? controller.setOpacity : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: <Widget>[
                      SizedBox(
                        width: 64,
                        child: AutoSizeText(
                          'Size',
                          maxLines: 1,
                          minFontSize: 10,
                          style: textTheme.labelMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Slider(
                          value: currentWidth,
                          min: 0.006,
                          max: 0.08,
                          divisions: 18,
                          onChanged: isLocked ? null : controller.setBrushWidth,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed:
                              isLocked || !hasStrokes ? null : controller.undo,
                          icon: const Icon(Icons.undo_rounded),
                          label: const Text('Undo'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed:
                              isLocked || !hasStrokes ? null : controller.clear,
                          icon: const Icon(Icons.layers_clear_outlined),
                          label: const Text('Clear'),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ] else ...<Widget>[
          Text(
            hasPuzzlePreview
                ? 'Switch back to Solution to keep drawing.'
                : 'Generate the puzzle from your solution when you are ready.',
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 16),
        TextField(
          controller: promptController,
          enabled: !isLocked && !isGeneratingPuzzle,
          textInputAction: TextInputAction.done,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: 'Puzzle Scene',
            filled: true,
            fillColor: colorScheme.surfaceContainerHighest,
            prefixIcon: const Icon(Icons.auto_awesome_outlined),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(color: colorScheme.outlineVariant),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(color: colorScheme.outlineVariant),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(color: colorScheme.primary, width: 2),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            SizedBox(
              width: 70,
              child: Text(
                'Hard',
                style: textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(
              child: Slider(
                value: generationDifficulty,
                min: 0.1,
                max: 3.0,
                divisions: 29,
                onChanged:
                    isLocked || isGeneratingPuzzle ? null : onGenerationDifficultyChanged,
              ),
            ),
            SizedBox(
              width: 70,
              child: Text(
                'Easy',
                textAlign: TextAlign.end,
                style: textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        Align(
          alignment: Alignment.center,
          child: Text(
            'Difficulty ${generationDifficulty.toStringAsFixed(1)}',
            style: textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (puzzleGenerationStatus.isNotEmpty) ...<Widget>[
          Text(
            puzzleGenerationStatus,
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
        ],
        FilledButton.icon(
          onPressed: isLocked || isGeneratingPuzzle ? null : onGeneratePuzzle,
          icon: Icon(
            hasPuzzlePreview
                ? Icons.refresh_rounded
                : Icons.auto_awesome_outlined,
          ),
          label: Text(
            isGeneratingPuzzle
                ? 'Generating...'
                : hasPuzzlePreview
                    ? 'Regenerate Puzzle'
                    : 'Generate Puzzle',
          ),
        ),
      ],
    );
  }
}

class _DrawingStage extends StatefulWidget {
  final DrawingController controller;
  final Color backgroundColor;
  final Color borderColor;
  final bool isLocked;
  final Offset Function(Offset localPosition, Size size) normalizePoint;
  final ValueChanged<bool> onInteractionChanged;

  const _DrawingStage({
    required this.controller,
    required this.backgroundColor,
    required this.borderColor,
    required this.isLocked,
    required this.normalizePoint,
    required this.onInteractionChanged,
  });

  @override
  State<_DrawingStage> createState() => _DrawingStageState();
}

class _DrawingStageState extends State<_DrawingStage> {
  int? _activePointerId;

  void _startStroke(PointerDownEvent event, Size size) {
    if (_activePointerId != null || event.buttons == 0) {
      return;
    }
    _activePointerId = event.pointer;
    widget.onInteractionChanged(true);
    widget.controller.startStroke(
      widget.normalizePoint(event.localPosition, size),
    );
  }

  void _appendStroke(PointerMoveEvent event, Size size) {
    if (_activePointerId != event.pointer) {
      return;
    }
    widget.controller.appendPoint(
      widget.normalizePoint(event.localPosition, size),
    );
  }

  void _finishStroke(int pointer) {
    if (_activePointerId != pointer) {
      return;
    }
    widget.controller.endStroke();
    _activePointerId = null;
    widget.onInteractionChanged(false);
  }

  @override
  void dispose() {
    if (_activePointerId != null) {
      widget.controller.endStroke();
      _activePointerId = null;
      widget.onInteractionChanged(false);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: widget.backgroundColor,
          border: Border.all(color: widget.borderColor),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(
              constraints.maxWidth,
              constraints.maxHeight,
            );

            return Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown:
                  widget.isLocked ? null : (event) => _startStroke(event, size),
              onPointerMove:
                  widget.isLocked ? null : (event) => _appendStroke(event, size),
              onPointerUp:
                  widget.isLocked ? null : (event) => _finishStroke(event.pointer),
              onPointerCancel:
                  widget.isLocked ? null : (event) => _finishStroke(event.pointer),
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  DrawingCanvas(
                    controller: widget.controller,
                    backgroundColor: widget.backgroundColor,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PuzzleStage extends StatelessWidget {
  final Uint8List? puzzleBytes;
  final Future<String>? existingPreviewUrlFuture;
  final bool hasStoredPuzzleImage;
  final bool isGeneratingPuzzle;
  final String statusText;
  final Color borderColor;
  final Color backgroundColor;
  final Color foregroundColor;

  const _PuzzleStage({
    required this.puzzleBytes,
    required this.existingPreviewUrlFuture,
    required this.hasStoredPuzzleImage,
    required this.isGeneratingPuzzle,
    required this.statusText,
    required this.borderColor,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hasLocalImage = puzzleBytes != null;
    final showStoredImage = !hasLocalImage && hasStoredPuzzleImage;
    final progressText = statusText.isNotEmpty ? statusText : 'Generating...';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (hasLocalImage)
              Image.memory(
                puzzleBytes!,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              )
            else if (showStoredImage)
              FutureBuilder<String>(
                future: existingPreviewUrlFuture,
                builder: (context, snapshot) {
                  final url = snapshot.data ?? '';
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(
                      child: SizedBox.square(
                        dimension: 24,
                        child: CircularProgressIndicator.adaptive(),
                      ),
                    );
                  }

                  if (url.isEmpty) {
                    return _PuzzleStagePlaceholder(
                      icon: Icons.image_not_supported_outlined,
                      title: 'Puzzle unavailable',
                      subtitle: 'The generated image could not be loaded.',
                      foregroundColor: foregroundColor,
                    );
                  }

                  return CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => const Center(
                      child: SizedBox.square(
                        dimension: 24,
                        child: CircularProgressIndicator.adaptive(),
                      ),
                    ),
                    errorWidget: (_, __, ___) => _PuzzleStagePlaceholder(
                      icon: Icons.image_not_supported_outlined,
                      title: 'Puzzle unavailable',
                      subtitle: 'The generated image could not be loaded.',
                      foregroundColor: foregroundColor,
                    ),
                  );
                },
              )
            else
              _PuzzleStagePlaceholder(
                icon: Icons.auto_awesome_outlined,
                title: 'Puzzle preview',
                subtitle: 'Generate the puzzle to see it here.',
                foregroundColor: foregroundColor,
              ),
            if (isGeneratingPuzzle)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: backgroundColor.withValues(alpha: 0.84),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const SizedBox.square(
                        dimension: 28,
                        child: CircularProgressIndicator.adaptive(),
                      ),
                      const SizedBox(height: 14),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          progressText,
                          textAlign: TextAlign.center,
                          style: textTheme.bodyMedium?.copyWith(
                            color: foregroundColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PuzzleStagePlaceholder extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color foregroundColor;

  const _PuzzleStagePlaceholder({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 40, color: foregroundColor),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: textTheme.titleSmall?.copyWith(
                color: foregroundColor,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: foregroundColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModePill extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final bool enabled;

  const _ModePill({
    required this.label,
    required this.icon,
    required this.selected,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final backgroundColor = selected
        ? colorScheme.primaryContainer
        : colorScheme.surfaceContainer;
    final foregroundColor = selected
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurface;

    return Opacity(
      opacity: enabled ? 1 : 0.56,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? colorScheme.primary : colorScheme.outlineVariant,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 18, color: foregroundColor),
              const SizedBox(width: 8),
              Flexible(
                child: AutoSizeText(
                  label,
                  maxLines: 1,
                  minFontSize: 10,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: foregroundColor,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrushButton extends StatelessWidget {
  final DrawingBrushType brush;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _BrushButton({
    required this.brush,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  IconData get _icon {
    switch (brush) {
      case DrawingBrushType.pencil:
        return Icons.edit_outlined;
      case DrawingBrushType.marker:
        return Icons.brush_outlined;
      case DrawingBrushType.charcoal:
        return Icons.texture_outlined;
      case DrawingBrushType.eraser:
        return Icons.auto_fix_off_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final backgroundColor = selected
        ? colorScheme.secondaryContainer
        : colorScheme.surfaceContainerHigh;
    final foregroundColor = selected
        ? colorScheme.onSecondaryContainer
        : colorScheme.onSurface;

    return Opacity(
      opacity: enabled ? 1 : 0.54,
      child: Material(
        color: backgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: selected ? colorScheme.secondary : colorScheme.outlineVariant,
          ),
        ),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            width: 132,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: <Widget>[
                Icon(_icon, color: foregroundColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: AutoSizeText(
                      brush.label,
                      maxLines: 1,
                      minFontSize: 10,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: foregroundColor,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LockedNotice extends StatelessWidget {
  final ColorScheme colorScheme;

  const _LockedNotice({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(Icons.lock_outline, color: colorScheme.onSecondaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'This level has already been submitted. It stays playable, but editing is locked so the reviewed version never shifts underneath moderation.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSecondaryContainer,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final Widget child;

  const _SectionCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    );
  }
}
