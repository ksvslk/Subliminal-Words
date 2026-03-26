import 'package:auto_size_text/auto_size_text.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:operation_hermes/controller/firebase_service.dart';
import 'package:operation_hermes/data/sw_level.dart';
import 'package:operation_hermes/data/user_level_metadata.dart';
import 'package:operation_hermes/data/word_letter_style.dart';
import 'package:operation_hermes/editor/content_filter.dart';
import 'package:operation_hermes/editor/drawing_canvas.dart';
import 'package:operation_hermes/editor/word_overlay_editor.dart';
import 'package:provider/provider.dart';

enum _StagePreviewMode {
  solution,
  puzzle,
}

class _EditorModeDraft {
  final String solution;
  final String creatorName;
  final String factHint;
  final String generationPrompt;
  final double generationDifficulty;
  final Map<String, dynamic> drawingEditorData;
  final Map<String, dynamic> wordDrawingEditorData;
  final List<Map<String, dynamic>> wordLetters;
  final Uint8List? generatedPuzzleImageBytes;
  final String puzzleGenerationStatus;
  final bool hasPuzzleInvalidatedByEdit;
  final _StagePreviewMode stagePreviewMode;

  const _EditorModeDraft({
    required this.solution,
    required this.creatorName,
    required this.factHint,
    required this.generationPrompt,
    required this.generationDifficulty,
    required this.drawingEditorData,
    required this.wordDrawingEditorData,
    required this.wordLetters,
    required this.generatedPuzzleImageBytes,
    required this.puzzleGenerationStatus,
    required this.hasPuzzleInvalidatedByEdit,
    required this.stagePreviewMode,
  });

  factory _EditorModeDraft.empty() {
    return const _EditorModeDraft(
      solution: '',
      creatorName: '',
      factHint: '',
      generationPrompt: '',
      generationDifficulty: 1.5,
      drawingEditorData: <String, dynamic>{},
      wordDrawingEditorData: <String, dynamic>{},
      wordLetters: <Map<String, dynamic>>[],
      generatedPuzzleImageBytes: null,
      puzzleGenerationStatus: '',
      hasPuzzleInvalidatedByEdit: false,
      stagePreviewMode: _StagePreviewMode.solution,
    );
  }
}

DrawingBrushType _brushFromName(String? name) {
  return DrawingBrushType.values.firstWhere(
    (brush) => brush.name == name,
    orElse: () => DrawingBrushType.none,
  );
}

DrawingController _buildDrawingControllerFromEditorData(
  Map<dynamic, dynamic>? rawEditorData,
) {
  final editorData = rawEditorData == null
      ? const <String, dynamic>{}
      : Map<String, dynamic>.from(rawEditorData);
  final initialStrokes = <DrawingStroke>[];
  final strokeJson =
      editorData['strokes'] as List<dynamic>? ?? const <dynamic>[];
  for (final stroke in strokeJson) {
    if (stroke is Map) {
      initialStrokes
          .add(DrawingStroke.fromJson(Map<String, dynamic>.from(stroke)));
    }
  }

  final brushSettings = editorData['brushSettings'] as Map<dynamic, dynamic>? ??
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

  return DrawingController(
    initialStrokes: initialStrokes,
    initialBrush: _brushFromName(editorData['selectedBrush'] as String?),
    initialBrushWidths: initialBrushWidths,
    initialBrushOpacities: initialBrushOpacities,
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
  static const int _minSolutionLength = 2;
  static const int _maxSolutionLength = 16;

  late final TextEditingController _creatorNameController;
  late final TextEditingController _answerController;
  late final TextEditingController _factController;
  late final TextEditingController _generationPromptController;
  late final FocusNode _generationPromptFocusNode;
  late final ValueNotifier<String> _creatorNameTextNotifier;
  late final ValueNotifier<String> _answerTextNotifier;
  late final ValueNotifier<String> _factTextNotifier;
  late final ValueNotifier<String> _generationPromptTextNotifier;
  late final DrawingController _drawingController;
  late final DrawingController _wordDrawingController;
  late final WordOverlayController _wordOverlayController;
  late final Future<String>? _existingPuzzlePreviewUrlFuture;

  bool _isSaving = false;
  bool _isGeneratingPuzzle = false;
  bool _isStageInteracting = false;
  bool _isLoadingWordEditorData = false;
  bool _isRestoringEditorModeDraft = false;
  double _generationDifficulty = 1.5;
  String _puzzleGenerationStatus = '';
  Uint8List? _generatedPuzzleImageBytes;
  _StagePreviewMode _stagePreviewMode = _StagePreviewMode.solution;
  bool _hasPuzzleInvalidatedByEdit = false;
  int _lastSeenDrawingContentVersion = 0;
  int _lastSeenWordDrawingContentVersion = 0;
  int _lastSeenWordContentVersion = 0;
  late String _editorMode;
  late final Map<String, _EditorModeDraft> _editorModeDrafts;

  bool get _isLocked => widget.initialLevel?.isLocked == true;
  bool get _isEditMode => widget.initialLevel != null;
  bool get _hasStoredPuzzleImage =>
      widget.initialLevel?.hasReviewReadyPuzzleImage == true &&
      !_hasPuzzleInvalidatedByEdit;
  bool get _hasPuzzleImageForReview =>
      _generatedPuzzleImageBytes != null || _hasStoredPuzzleImage;
  bool get _canSubmitForReview => _validateInputs(forSubmission: true) == null;
  bool get _hasSolutionText =>
      _answerController.text.trim().length >= _minSolutionLength;
  bool get _hasPuzzlePrompt =>
      _generationPromptController.text.trim().isNotEmpty;
  bool get _hasCreatorName => _creatorNameController.text.trim().isNotEmpty;
  bool get _hasFactHint =>
      _editorMode == UserLevelEditorMode.highlight ||
      _factController.text.trim().isNotEmpty;
  bool get _hasSolutionStageContent =>
      _editorMode == UserLevelEditorMode.highlight
          ? _wordOverlayController.hasLetters
          : _drawingController.hasCommittedStrokes;
  bool get _canAccessPuzzleStep => _isLocked || _isSolutionStepComplete;

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
    _creatorNameTextNotifier =
        ValueNotifier<String>(_creatorNameController.text);
    _answerTextNotifier = ValueNotifier<String>(_answerController.text);
    _factTextNotifier = ValueNotifier<String>(_factController.text);
    _editorMode = initialLevel?.editorMode == UserLevelEditorMode.highlight
        ? UserLevelEditorMode.highlight
        : UserLevelEditorMode.drawObject;
    _generationPromptController = TextEditingController(
      text: initialEditorData['generationPrompt'] as String? ??
          initialLevel?.name ??
          '',
    );
    _generationPromptTextNotifier = ValueNotifier<String>(
      _generationPromptController.text,
    );
    _generationPromptFocusNode = FocusNode();
    _generationDifficulty =
        (initialEditorData['generationDifficulty'] as num?)?.toDouble() ?? 1.5;

    _drawingController =
        _buildDrawingControllerFromEditorData(initialEditorData);
    _wordDrawingController = _buildDrawingControllerFromEditorData(
      initialEditorData['wordDrawing'] as Map<dynamic, dynamic>?,
    );
    final initialWordLettersJson =
        initialEditorData['wordLetters'] as List<dynamic>? ?? const <dynamic>[];
    _wordOverlayController = WordOverlayController(
      initialLetters: initialWordLettersJson.whereType<Map>().map(
            (letterJson) => WordOverlayLetter.fromJson(
              Map<String, dynamic>.from(letterJson),
            ),
          ),
    );
    _lastSeenDrawingContentVersion = _drawingController.contentVersion;
    _lastSeenWordDrawingContentVersion = _wordDrawingController.contentVersion;
    _lastSeenWordContentVersion = _wordOverlayController.contentVersion;
    _drawingController.addListener(_handleDrawingControllerChanged);
    _wordDrawingController.addListener(_handleWordDrawingControllerChanged);
    _wordOverlayController.addListener(_handleWordOverlayControllerChanged);
    _creatorNameController.addListener(_handleCreatorNameChanged);
    _answerController.addListener(_handleAnswerChanged);
    _factController.addListener(_handleFactChanged);
    _generationPromptController.addListener(_handleGenerationPromptChanged);
    _existingPuzzlePreviewUrlFuture = _hasStoredPuzzleImage
        ? context
            .read<FirebaseService>()
            .getDownloadUrl(initialLevel!.puzzlePath)
        : null;
    _editorModeDrafts = <String, _EditorModeDraft>{
      UserLevelEditorMode.drawObject: _EditorModeDraft.empty(),
      UserLevelEditorMode.highlight: _EditorModeDraft.empty(),
    };
    _editorModeDrafts[_editorMode] = _captureCurrentModeDraft();
    if (_editorMode == UserLevelEditorMode.highlight &&
        !_wordOverlayController.hasLetters &&
        (initialLevel?.solutionPath.isNotEmpty ?? false)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadExistingWordLetters();
      });
    }
  }

  @override
  void dispose() {
    _creatorNameController.dispose();
    _answerController.dispose();
    _factController.dispose();
    _generationPromptController.dispose();
    _generationPromptFocusNode.dispose();
    _creatorNameTextNotifier.dispose();
    _answerTextNotifier.dispose();
    _factTextNotifier.dispose();
    _generationPromptTextNotifier.dispose();
    _drawingController.removeListener(_handleDrawingControllerChanged);
    _wordDrawingController.removeListener(_handleWordDrawingControllerChanged);
    _wordOverlayController.removeListener(_handleWordOverlayControllerChanged);
    _creatorNameController.removeListener(_handleCreatorNameChanged);
    _answerController.removeListener(_handleAnswerChanged);
    _factController.removeListener(_handleFactChanged);
    _generationPromptController.removeListener(_handleGenerationPromptChanged);
    _drawingController.dispose();
    _wordDrawingController.dispose();
    _wordOverlayController.dispose();
    super.dispose();
  }

  Color _canvasBackgroundColor(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    if (theme.brightness == Brightness.dark) {
      return colorScheme.inverseSurface;
    }

    return colorScheme.surface;
  }

  void _handleDrawingControllerChanged() {
    if (_isRestoringEditorModeDraft) {
      _lastSeenDrawingContentVersion = _drawingController.contentVersion;
      return;
    }
    final contentVersion = _drawingController.contentVersion;
    if (contentVersion == _lastSeenDrawingContentVersion) {
      return;
    }

    _lastSeenDrawingContentVersion = contentVersion;
    _invalidatePuzzlePreview();
  }

  void _handleWordOverlayControllerChanged() {
    if (_isRestoringEditorModeDraft) {
      _lastSeenWordContentVersion = _wordOverlayController.contentVersion;
      return;
    }
    final contentVersion = _wordOverlayController.contentVersion;
    if (contentVersion == _lastSeenWordContentVersion) {
      return;
    }

    _lastSeenWordContentVersion = contentVersion;
    _invalidatePuzzlePreview();
  }

  void _handleWordDrawingControllerChanged() {
    if (_isRestoringEditorModeDraft) {
      _lastSeenWordDrawingContentVersion =
          _wordDrawingController.contentVersion;
      return;
    }
    final contentVersion = _wordDrawingController.contentVersion;
    if (contentVersion == _lastSeenWordDrawingContentVersion) {
      return;
    }

    _lastSeenWordDrawingContentVersion = contentVersion;
    _invalidatePuzzlePreview();
  }

  void _handleAnswerChanged() {
    final text = _answerController.text;
    final uppercased = text.toUpperCase();
    if (text != uppercased) {
      _answerController.value = _answerController.value.copyWith(
        text: uppercased,
        selection: TextSelection.collapsed(offset: uppercased.length),
        composing: TextRange.empty,
      );
      return;
    }
    if (text == _answerTextNotifier.value) {
      return;
    }
    _answerTextNotifier.value = text;
    if (_editorMode == UserLevelEditorMode.highlight) {
      _wordOverlayController.syncToSolution(text);
    }
    _handleGenerationInputsChanged();
  }

  _EditorModeDraft _captureCurrentModeDraft() {
    return _EditorModeDraft(
      solution: _answerController.text,
      creatorName: _creatorNameController.text,
      factHint: _factController.text,
      generationPrompt: _generationPromptController.text,
      generationDifficulty: _generationDifficulty,
      drawingEditorData: _drawingController.toEditorData(),
      wordDrawingEditorData: _wordDrawingController.toEditorData(),
      wordLetters: _wordOverlayController.letters
          .map((letter) => letter.toJson())
          .toList(growable: false),
      generatedPuzzleImageBytes: _generatedPuzzleImageBytes == null
          ? null
          : Uint8List.fromList(_generatedPuzzleImageBytes!),
      puzzleGenerationStatus: _puzzleGenerationStatus,
      hasPuzzleInvalidatedByEdit: _hasPuzzleInvalidatedByEdit,
      stagePreviewMode: _stagePreviewMode,
    );
  }

  bool _draftHasSolutionStageContent(_EditorModeDraft draft, String mode) {
    if (mode == UserLevelEditorMode.highlight) {
      final expectedLetters =
          extractWordSolutionCharacters(draft.solution.trim());
      return expectedLetters.isNotEmpty &&
          draft.wordLetters.length == expectedLetters.length;
    }

    final strokes = draft.drawingEditorData['strokes'] as List<dynamic>? ??
        const <dynamic>[];
    return strokes.isNotEmpty;
  }

  bool _draftCanAccessPuzzleStep(_EditorModeDraft draft, String mode) {
    return draft.solution.trim().length >= _minSolutionLength &&
        _draftHasSolutionStageContent(draft, mode);
  }

  void _restoreModeDraft(String mode) {
    final draft = _editorModeDrafts[mode] ?? _EditorModeDraft.empty();
    final canAccessPuzzleStep = _draftCanAccessPuzzleStep(draft, mode);

    _isRestoringEditorModeDraft = true;
    try {
      _creatorNameController.text = draft.creatorName;
      _factController.text = draft.factHint;
      _generationPromptController.text = draft.generationPrompt;
      _answerController.text = draft.solution;
      _drawingController.replaceFromEditorData(draft.drawingEditorData);
      _wordDrawingController.replaceFromEditorData(draft.wordDrawingEditorData);
      _wordOverlayController.replaceLetters(
        draft.wordLetters.map(WordOverlayLetter.fromJson),
      );
      _generationDifficulty = draft.generationDifficulty;
      _generatedPuzzleImageBytes = draft.generatedPuzzleImageBytes == null
          ? null
          : Uint8List.fromList(draft.generatedPuzzleImageBytes!);
      _puzzleGenerationStatus = draft.puzzleGenerationStatus;
      _hasPuzzleInvalidatedByEdit = draft.hasPuzzleInvalidatedByEdit;
      _stagePreviewMode = canAccessPuzzleStep
          ? draft.stagePreviewMode
          : _StagePreviewMode.solution;
    } finally {
      _isRestoringEditorModeDraft = false;
    }
  }

  void _handleCreatorNameChanged() {
    final text = _creatorNameController.text;
    if (text == _creatorNameTextNotifier.value) {
      return;
    }
    _creatorNameTextNotifier.value = text;
  }

  void _handleFactChanged() {
    final text = _factController.text;
    if (text == _factTextNotifier.value) {
      return;
    }
    _factTextNotifier.value = text;
    _handleGenerationInputsChanged();
  }

  void _handleGenerationPromptChanged() {
    final text = _generationPromptController.text;
    if (text == _generationPromptTextNotifier.value) {
      return;
    }
    _generationPromptTextNotifier.value = text;
    _handleGenerationInputsChanged();
  }

  void _handleGenerationInputsChanged() {
    if (_isRestoringEditorModeDraft) {
      return;
    }
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

  Future<void> _loadExistingWordLetters() async {
    final initialLevel = widget.initialLevel;
    if (initialLevel == null ||
        _editorMode != UserLevelEditorMode.highlight ||
        initialLevel.solutionPath.isEmpty ||
        _wordOverlayController.hasLetters) {
      return;
    }

    if (mounted) {
      setState(() => _isLoadingWordEditorData = true);
    }

    try {
      final firebaseService = context.read<FirebaseService>();
      final svgUrl =
          await firebaseService.getDownloadUrl(initialLevel.solutionPath);
      if (svgUrl.isEmpty) {
        return;
      }

      final response = await http.get(Uri.parse(svgUrl));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('Could not load the existing word overlay.');
      }

      final letters = parseWordOverlayLetters(response.body);
      if (!mounted || letters.isEmpty) {
        return;
      }

      _wordOverlayController.replaceLetters(letters);
      _lastSeenWordContentVersion = _wordOverlayController.contentVersion;
    } catch (_) {
      // If the existing overlay cannot be parsed, the editor can still rebuild it.
    } finally {
      if (mounted) {
        setState(() => _isLoadingWordEditorData = false);
      }
    }
  }

  void _setEditorMode(String mode) {
    if (_isEditMode ||
        _isLocked ||
        _editorMode == mode ||
        _isSaving ||
        _isGeneratingPuzzle) {
      return;
    }

    _editorModeDrafts[_editorMode] = _captureCurrentModeDraft();
    setState(() {
      _editorMode = mode;
      _isStageInteracting = false;
      _restoreModeDraft(mode);
    });
  }

  List<WordOverlayLetter> _wordSolutionTemplates() {
    return buildWordOverlayLettersFromSolution(_answerController.text.trim());
  }

  bool get _isSolutionStepComplete {
    return _hasSolutionText && _hasSolutionStageContent;
  }

  double get _solutionStepProgress {
    final checkpoints = <bool>[
      _hasSolutionText,
      _hasSolutionStageContent,
    ];
    final completeCount = checkpoints.where((checkpoint) => checkpoint).length;
    return completeCount / checkpoints.length;
  }

  double get _puzzleStepProgress {
    if (!_canAccessPuzzleStep) {
      return 0;
    }

    final checkpoints = <bool>[
      _hasPuzzlePrompt,
      _hasPuzzleImageForReview,
      _hasCreatorName,
      if (_editorMode != UserLevelEditorMode.highlight) _hasFactHint,
    ];
    final completeCount = checkpoints.where((checkpoint) => checkpoint).length;
    return completeCount / checkpoints.length;
  }

  void _selectStagePreview(
    _StagePreviewMode mode, {
    bool requestPromptFocus = false,
  }) {
    if (!mounted) {
      return;
    }

    if (mode == _StagePreviewMode.puzzle &&
        !_isLocked &&
        !_isSolutionStepComplete) {
      _showSnack('Finish Step 1 before moving to the puzzle.');
      return;
    }

    if (_stagePreviewMode == mode) {
      if (requestPromptFocus && mode == _StagePreviewMode.puzzle) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _generationPromptFocusNode.requestFocus();
          }
        });
      }
      return;
    }

    setState(() => _stagePreviewMode = mode);
    if (requestPromptFocus && mode == _StagePreviewMode.puzzle) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _generationPromptFocusNode.requestFocus();
        }
      });
    }
  }

  Future<void> _generatePuzzle() async {
    if (_isLocked || _isGeneratingPuzzle) {
      return;
    }

    final validationMessage = _validateGenerationInputs();
    if (validationMessage != null) {
      _showSnack(validationMessage);
      return;
    }

    final prompt = _generationPromptController.text.trim();

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
      final solutionBytes = _editorMode == UserLevelEditorMode.highlight
          ? await exportWordOverlayAsPng(
              letters: _wordOverlayController.letters,
              strokes: _wordDrawingController.strokes,
              backgroundColor: _generationExportBackground,
            )
          : await exportDrawingAsPng(
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

  String? _validateGenerationInputs() {
    final solution = _answerController.text.trim();
    final prompt = _generationPromptController.text.trim();

    if (solution.length < _minSolutionLength) {
      return 'Add the solution before generating.';
    }
    if (solution.length > _maxSolutionLength) {
      return 'Keep the solution to $_maxSolutionLength characters or fewer.';
    }
    if (prompt.isEmpty) {
      return 'Add a puzzle scene before generating.';
    }

    if (_editorMode == UserLevelEditorMode.highlight) {
      final expectedTemplates = _wordSolutionTemplates();
      if (!_wordOverlayController.hasLetters) {
        return 'Add the solution letters to the stage before generating.';
      }
      if (_wordOverlayController.letters.length != expectedTemplates.length) {
        return 'Add the solution letters again so they match the solution.';
      }
    } else if (!_drawingController.hasCommittedStrokes) {
      return 'Draw something before generating.';
    }

    for (final value in <String>[solution, prompt]) {
      if (ContentFilter.containsBlockedTerm(value)) {
        return 'Please remove profanity before generating.';
      }
    }

    return null;
  }

  String? _validateInputs({required bool forSubmission}) {
    final creatorName = _creatorNameController.text.trim();
    final answer = _answerController.text.trim();
    final factHint = _factController.text.trim();

    if (creatorName.isEmpty) {
      return 'Add a public creator name before saving.';
    }
    if (answer.length < _minSolutionLength) {
      return 'Add the solution with at least $_minSolutionLength characters.';
    }
    if (answer.length > _maxSolutionLength) {
      return 'Keep the solution to $_maxSolutionLength characters or fewer.';
    }
    if (_editorMode != UserLevelEditorMode.highlight && factHint.isEmpty) {
      return 'Add a fact hint before saving.';
    }

    if (_editorMode == UserLevelEditorMode.highlight) {
      final expectedTemplates = _wordSolutionTemplates();
      if (!_wordOverlayController.hasLetters) {
        return 'Add the solution letters to the stage before saving.';
      }
      if (_wordOverlayController.letters.length != expectedTemplates.length) {
        return 'Add the solution letters again so they match the solution.';
      }

      final placedById = <String, WordOverlayLetter>{
        for (final letter in _wordOverlayController.letters) letter.id: letter,
      };
      for (final template in expectedTemplates) {
        final placedLetter = placedById[template.id];
        if (placedLetter == null ||
            placedLetter.letter.toUpperCase() !=
                template.letter.toUpperCase()) {
          return 'Add the solution letters again so they match the solution.';
        }
      }
      if (forSubmission && !_hasPuzzleImageForReview) {
        return 'Generate the puzzle before submitting for review.';
      }
    } else {
      if (!_drawingController.hasCommittedStrokes) {
        return 'Draw something before saving.';
      }
      if (forSubmission && !_hasPuzzleImageForReview) {
        return 'Generate the puzzle before submitting for review.';
      }
    }

    final profanityCheckedValues = <String>[
      creatorName,
      answer,
      if (_editorMode != UserLevelEditorMode.highlight) factHint,
    ];
    for (final value in profanityCheckedValues) {
      if (ContentFilter.containsBlockedTerm(value)) {
        return 'Please remove profanity before saving.';
      }
    }

    return null;
  }

  Future<void> _save({required bool submitAfterSave}) async {
    final validationMessage = _validateInputs(forSubmission: submitAfterSave);
    if (validationMessage != null) {
      _showSnack(validationMessage);
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isSaving = true);
    final firebaseService = context.read<FirebaseService>();

    try {
      late final String levelId;
      if (_editorMode == UserLevelEditorMode.highlight) {
        final editorData = <String, dynamic>{
          'wordLetters': _wordOverlayController.letters
              .map((letter) => letter.toJson())
              .toList(),
          'wordDrawing': _wordDrawingController.toEditorData(),
          'generationPrompt': _generationPromptController.text.trim(),
          'generationDifficulty': _generationDifficulty,
        };

        levelId = await firebaseService.saveWordLevel(
          levelId: widget.initialLevel?.documentId,
          creatorName: _creatorNameController.text,
          answer: _answerController.text,
          factText: '',
          solutionSvg: generateWordOverlaySvg(_wordOverlayController.letters),
          puzzleImageBytes: _generatedPuzzleImageBytes,
          allowReuseExistingPuzzle: !_hasPuzzleInvalidatedByEdit,
          editorData: editorData,
        );
      } else {
        final pngBytes = await exportDrawingAsPng(
          strokes: _drawingController.strokes,
          backgroundColor: _generationExportBackground,
        );
        final editorData = _drawingController.toEditorData()
          ..['generationPrompt'] = _generationPromptController.text.trim()
          ..['generationDifficulty'] = _generationDifficulty;

        levelId = await firebaseService.saveDrawObjectLevel(
          levelId: widget.initialLevel?.documentId,
          creatorName: _creatorNameController.text,
          answer: _answerController.text,
          factText: _factController.text,
          solutionPngBytes: pngBytes,
          puzzleImageBytes: _generatedPuzzleImageBytes,
          allowReuseExistingPuzzle: !_hasPuzzleInvalidatedByEdit,
          editorData: editorData,
        );
      }

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
                  _creatorNameTextNotifier,
                  _answerTextNotifier,
                  _factTextNotifier,
                  _generationPromptTextNotifier,
                  _drawingController,
                  _wordDrawingController,
                  _wordOverlayController,
                ]),
                builder: (context, _) => Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _EditorStepProgress(
                      textTheme: textTheme,
                      colorScheme: colorScheme,
                      activeStep: _stagePreviewMode,
                      solutionProgress: _solutionStepProgress,
                      puzzleProgress: _puzzleStepProgress,
                      canAccessPuzzleStep: _canAccessPuzzleStep,
                      onStepSelected: _selectStagePreview,
                    ),
                    const SizedBox(height: 12),
                    Row(
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
                            onPressed:
                                _isSaving || _isLocked || !_canSubmitForReview
                                    ? null
                                    : () => _save(submitAfterSave: true),
                            child: Text(
                              _isSaving ? 'Submitting...' : 'Submit for Review',
                            ),
                          ),
                        ),
                      ],
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
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _SectionCard(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
                  child: _editorMode == UserLevelEditorMode.highlight
                      ? _WordEditorSection(
                          controller: _wordOverlayController,
                          drawingController: _wordDrawingController,
                          solutionController: _answerController,
                          solutionTextListenable: _answerTextNotifier,
                          creatorNameController: _creatorNameController,
                          promptController: _generationPromptController,
                          promptTextListenable: _generationPromptTextNotifier,
                          textTheme: textTheme,
                          colorScheme: colorScheme,
                          canvasBackgroundColor: canvasBackgroundColor,
                          isLocked: _isLocked,
                          isLoadingInitialOverlay: _isLoadingWordEditorData,
                          stagePreviewMode: _stagePreviewMode,
                          puzzleBytes: _generatedPuzzleImageBytes,
                          existingPuzzlePreviewUrlFuture:
                              _existingPuzzlePreviewUrlFuture,
                          hasStoredPuzzleImage: _hasStoredPuzzleImage,
                          isGeneratingPuzzle: _isGeneratingPuzzle,
                          puzzleGenerationStatus: _puzzleGenerationStatus,
                          generationDifficulty: _generationDifficulty,
                          onStageInteractionChanged:
                              _handleStageInteractionChanged,
                          normalizePoint: _normalizePoint,
                          onSelectStagePreview: _selectStagePreview,
                          onGeneratePuzzle: _generatePuzzle,
                          onGenerationDifficultyChanged: (value) => setState(
                            () => _generationDifficulty = value,
                          ),
                          generationPromptFocusNode: _generationPromptFocusNode,
                          isSolutionStepComplete: _isSolutionStepComplete,
                        )
                      : _CanvasEditorSection(
                          controller: _drawingController,
                          solutionController: _answerController,
                          solutionTextListenable: _answerTextNotifier,
                          factController: _factController,
                          creatorNameController: _creatorNameController,
                          promptController: _generationPromptController,
                          promptTextListenable: _generationPromptTextNotifier,
                          textTheme: textTheme,
                          colorScheme: colorScheme,
                          canvasBackgroundColor: canvasBackgroundColor,
                          isLocked: _isLocked,
                          stagePreviewMode: _stagePreviewMode,
                          puzzleBytes: _generatedPuzzleImageBytes,
                          existingPuzzlePreviewUrlFuture:
                              _existingPuzzlePreviewUrlFuture,
                          hasStoredPuzzleImage: _hasStoredPuzzleImage,
                          isGeneratingPuzzle: _isGeneratingPuzzle,
                          puzzleGenerationStatus: _puzzleGenerationStatus,
                          generationDifficulty: _generationDifficulty,
                          normalizePoint: _normalizePoint,
                          onStageInteractionChanged:
                              _handleStageInteractionChanged,
                          onSelectStagePreview: _selectStagePreview,
                          onGeneratePuzzle: _generatePuzzle,
                          onGenerationDifficultyChanged: (value) => setState(
                            () => _generationDifficulty = value,
                          ),
                          generationPromptFocusNode: _generationPromptFocusNode,
                          isSolutionStepComplete: _isSolutionStepComplete,
                        ),
                ),
                const SizedBox(height: 16),
                _SectionCard(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: _CreatorModesFooter(
                    textTheme: textTheme,
                    colorScheme: colorScheme,
                    selectedMode: _editorMode,
                    canChangeMode: !_isEditMode &&
                        !_isLocked &&
                        !_isSaving &&
                        !_isGeneratingPuzzle,
                    onModeSelected: _setEditorMode,
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
  final TextEditingController solutionController;
  final ValueNotifier<String> solutionTextListenable;
  final TextEditingController factController;
  final TextEditingController creatorNameController;
  final TextEditingController promptController;
  final FocusNode generationPromptFocusNode;
  final ValueNotifier<String> promptTextListenable;
  final TextTheme textTheme;
  final ColorScheme colorScheme;
  final Color canvasBackgroundColor;
  final bool isLocked;
  final bool isSolutionStepComplete;
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
    required this.solutionController,
    required this.solutionTextListenable,
    required this.factController,
    required this.creatorNameController,
    required this.promptController,
    required this.generationPromptFocusNode,
    required this.promptTextListenable,
    required this.textTheme,
    required this.colorScheme,
    required this.canvasBackgroundColor,
    required this.isLocked,
    required this.isSolutionStepComplete,
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
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        controller,
        solutionTextListenable,
        promptTextListenable,
      ]),
      builder: (context, _) {
        final hasPuzzlePreview = puzzleBytes != null || hasStoredPuzzleImage;
        final canGeneratePuzzleNow = !isLocked &&
            solutionTextListenable.value.trim().length >= 2 &&
            promptTextListenable.value.trim().isNotEmpty &&
            controller.hasCommittedStrokes;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            AnimatedBuilder(
              animation: controller,
              builder: (context, _) {
                final hasStrokes = controller.hasCommittedStrokes;
                final canEditCanvas =
                    stagePreviewMode == _StagePreviewMode.solution &&
                        !isLocked &&
                        hasStrokes;

                return Row(
                  children: <Widget>[
                    SizedBox(
                      width: 86,
                      child: Row(
                        children: <Widget>[
                          _CompactActionButton(
                            icon: Icons.undo_rounded,
                            label: 'Undo',
                            enabled: canEditCanvas,
                            onPressed: controller.undo,
                            dimension: 40,
                          ),
                          const SizedBox(width: 6),
                          _CompactActionButton(
                            icon: Icons.delete_outline_rounded,
                            label: 'Delete',
                            enabled: canEditCanvas,
                            onPressed: controller.clear,
                            dimension: 40,
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    const SizedBox(width: 8),
                    _StageStepToggle(
                      value: stagePreviewMode,
                      canAccessPuzzleStep: isLocked || isSolutionStepComplete,
                      textTheme: textTheme,
                      onChanged: isLocked ? null : onSelectStagePreview,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
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
                      solutionBackdrop: IgnorePointer(
                        child: Opacity(
                          opacity: 0.14,
                          child: DrawingCanvas(
                            controller: controller,
                            backgroundColor: canvasBackgroundColor,
                            paintBackground: false,
                          ),
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 8),
            if (stagePreviewMode == _StagePreviewMode.solution) ...<Widget>[
              AnimatedBuilder(
                animation: controller,
                builder: (context, _) {
                  final selectedBrush = controller.selectedBrush;
                  final currentOpacity = controller.currentOpacity;
                  final currentWidth = controller.currentWidth;
                  final canAdjustOpacity =
                      selectedBrush != DrawingBrushType.eraser &&
                          selectedBrush != DrawingBrushType.none;
                  final canAdjustSize = selectedBrush != DrawingBrushType.none;

                  return Column(
                    children: <Widget>[
                      SizedBox(
                        height: 48,
                        child: _BrushSelectorStrip(
                          selectedBrush: selectedBrush,
                          enabled: !isLocked,
                          onSelectBrush: controller.selectBrush,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: _CompactSliderTile(
                              label: selectedBrush == DrawingBrushType.none
                                  ? 'Opacity'
                                  : canAdjustOpacity
                                      ? 'Opacity'
                                      : 'Eraser',
                              valueText: selectedBrush == DrawingBrushType.none
                                  ? 'Off'
                                  : canAdjustOpacity
                                      ? '${(currentOpacity * 100).round()}%'
                                      : 'On',
                              child: Opacity(
                                opacity: canAdjustOpacity ? 1 : 0.45,
                                child: SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    trackHeight: 3,
                                    thumbShape: const RoundSliderThumbShape(
                                      enabledThumbRadius: 8,
                                    ),
                                    overlayShape: const RoundSliderOverlayShape(
                                      overlayRadius: 14,
                                    ),
                                  ),
                                  child: Slider(
                                    value: currentOpacity,
                                    min: 0.2,
                                    max: 1.0,
                                    divisions: 8,
                                    onChanged: canAdjustOpacity
                                        ? controller.setOpacity
                                        : null,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _CompactSliderTile(
                              label: 'Size',
                              valueText: canAdjustSize
                                  ? '${(currentWidth * 1000).round()}'
                                  : 'Off',
                              child: Opacity(
                                opacity: canAdjustSize ? 1 : 0.45,
                                child: SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    trackHeight: 3,
                                    thumbShape: const RoundSliderThumbShape(
                                      enabledThumbRadius: 8,
                                    ),
                                    overlayShape: const RoundSliderOverlayShape(
                                      overlayRadius: 14,
                                    ),
                                  ),
                                  child: Slider(
                                    value: currentWidth,
                                    min: 0.006,
                                    max: 0.08,
                                    divisions: 18,
                                    onChanged: isLocked || !canAdjustSize
                                        ? null
                                        : controller.setBrushWidth,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: solutionController,
                enabled: !isLocked,
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                enableSuggestions: false,
                inputFormatters: <TextInputFormatter>[
                  LengthLimitingTextInputFormatter(
                      _CreateLevelScreenState._maxSolutionLength),
                ],
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                ),
                decoration: _solutionFieldDecoration(colorScheme),
              ),
            ] else ...<Widget>[
              TextField(
                controller: promptController,
                focusNode: generationPromptFocusNode,
                enabled: !isLocked && !isGeneratingPuzzle,
                textInputAction: TextInputAction.done,
                maxLines: 2,
                decoration: _sharedFieldDecoration(
                  colorScheme,
                  label: 'Puzzle Scene',
                  icon: Icons.auto_awesome_outlined,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: <Widget>[
                  SizedBox(
                    width: 54,
                    child: Text(
                      'Hard',
                      style: textTheme.labelMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 8,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 14,
                        ),
                      ),
                      child: Slider(
                        value: generationDifficulty,
                        min: 0.1,
                        max: 3.0,
                        divisions: 29,
                        onChanged: isLocked || isGeneratingPuzzle
                            ? null
                            : onGenerationDifficultyChanged,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 54,
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
                  style: textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: isGeneratingPuzzle || !canGeneratePuzzleNow
                      ? null
                      : onGeneratePuzzle,
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
              ),
              if (puzzleGenerationStatus.isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                Text(
                  puzzleGenerationStatus,
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: factController,
                enabled: !isLocked,
                textInputAction: TextInputAction.next,
                maxLines: 2,
                decoration: _sharedFieldDecoration(
                  colorScheme,
                  label: 'Fact Hint',
                  icon: Icons.lightbulb_outline,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: creatorNameController,
                enabled: !isLocked,
                textCapitalization: TextCapitalization.words,
                decoration: _sharedFieldDecoration(
                  colorScheme,
                  label: 'Creator Name',
                  icon: Icons.badge_outlined,
                ),
              ),
            ],
          ],
        );
      },
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
    if (_activePointerId != null ||
        event.buttons == 0 ||
        widget.isLocked ||
        !widget.controller.canDraw) {
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: widget.backgroundColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: widget.borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(1),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(23),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(
                constraints.maxWidth,
                constraints.maxHeight,
              );

              final stageChild = Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  DrawingCanvas(
                    controller: widget.controller,
                    backgroundColor: widget.backgroundColor,
                  ),
                  IgnorePointer(
                    child: AnimatedBuilder(
                      animation: widget.controller,
                      builder: (context, _) {
                        final showHint =
                            !widget.controller.hasCommittedStrokes &&
                                widget.controller.activeStroke == null;
                        if (!showHint) {
                          return const SizedBox.shrink();
                        }

                        return _StagePlaceholder(
                          icon: Icons.gesture_outlined,
                          title: 'Solution preview',
                          subtitle: 'Draw the solution here.',
                          foregroundColor:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        );
                      },
                    ),
                  ),
                ],
              );

              return Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (event) => _startStroke(event, size),
                onPointerMove: (event) => _appendStroke(event, size),
                onPointerUp: (event) => _finishStroke(event.pointer),
                onPointerCancel: (event) => _finishStroke(event.pointer),
                child: stageChild,
              );
            },
          ),
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
  final Widget? solutionBackdrop;

  const _PuzzleStage({
    required this.puzzleBytes,
    required this.existingPreviewUrlFuture,
    required this.hasStoredPuzzleImage,
    required this.isGeneratingPuzzle,
    required this.statusText,
    required this.borderColor,
    required this.backgroundColor,
    required this.foregroundColor,
    this.solutionBackdrop,
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
      child: Padding(
        padding: const EdgeInsets.all(1),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(23),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              if (solutionBackdrop != null &&
                  !hasLocalImage &&
                  !showStoredImage)
                solutionBackdrop!,
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
                      return _StagePlaceholder(
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
                      errorWidget: (_, __, ___) => _StagePlaceholder(
                        icon: Icons.image_not_supported_outlined,
                        title: 'Puzzle unavailable',
                        subtitle: 'The generated image could not be loaded.',
                        foregroundColor: foregroundColor,
                      ),
                    );
                  },
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
      ),
    );
  }
}

class _StagePlaceholder extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color foregroundColor;

  const _StagePlaceholder({
    required this.icon,
    required this.title,
    this.subtitle = '',
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
            if (subtitle.isNotEmpty) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  color: foregroundColor,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

InputDecoration _sharedFieldDecoration(
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
    fillColor: colorScheme.surface,
    border: border,
    enabledBorder: border,
    disabledBorder: border,
    focusedBorder: border.copyWith(
      borderSide: BorderSide(color: colorScheme.primary, width: 2),
    ),
  );
}

InputDecoration _solutionFieldDecoration(
  ColorScheme colorScheme, {
  String label = 'Solution',
  String hint = 'What should players guess?',
}) {
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(20),
    borderSide: BorderSide(color: colorScheme.outlineVariant),
  );

  return InputDecoration(
    labelText: label,
    hintText: hint,
    prefixIcon: const Icon(Icons.track_changes_outlined),
    filled: true,
    fillColor: colorScheme.surface,
    border: border,
    enabledBorder: border,
    disabledBorder: border,
    focusedBorder: border.copyWith(
      borderSide: BorderSide(color: colorScheme.primary, width: 2),
    ),
  );
}

class _StageStepToggle extends StatelessWidget {
  final _StagePreviewMode value;
  final ValueChanged<_StagePreviewMode>? onChanged;
  final TextTheme textTheme;
  final bool canAccessPuzzleStep;

  const _StageStepToggle({
    required this.value,
    required this.onChanged,
    required this.textTheme,
    required this.canAccessPuzzleStep,
  });

  @override
  Widget build(BuildContext context) {
    final compactSegmentStyle = ButtonStyle(
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
        EdgeInsets.symmetric(horizontal: 6, vertical: 0),
      ),
      textStyle: WidgetStatePropertyAll<TextStyle?>(
        textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
    );

    return SegmentedButton<_StagePreviewMode>(
      style: compactSegmentStyle,
      segments: <ButtonSegment<_StagePreviewMode>>[
        ButtonSegment<_StagePreviewMode>(
          value: _StagePreviewMode.solution,
          label: Text('1. Solution'),
        ),
        ButtonSegment<_StagePreviewMode>(
          value: _StagePreviewMode.puzzle,
          label: Text('2. Puzzle'),
          enabled: canAccessPuzzleStep,
        ),
      ],
      selected: <_StagePreviewMode>{value},
      showSelectedIcon: false,
      onSelectionChanged:
          onChanged == null ? null : (selection) => onChanged!(selection.first),
    );
  }
}

class _EditorStepProgress extends StatelessWidget {
  final double solutionProgress;
  final double puzzleProgress;
  final _StagePreviewMode activeStep;
  final ColorScheme colorScheme;
  final TextTheme textTheme;
  final bool canAccessPuzzleStep;
  final ValueChanged<_StagePreviewMode> onStepSelected;

  const _EditorStepProgress({
    required this.solutionProgress,
    required this.puzzleProgress,
    required this.activeStep,
    required this.colorScheme,
    required this.textTheme,
    required this.canAccessPuzzleStep,
    required this.onStepSelected,
  });

  @override
  Widget build(BuildContext context) {
    final solutionActive = activeStep == _StagePreviewMode.solution;

    return SizedBox(
      height: 46,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.82),
          ),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
                child: _StepProgressTapArea(
                  label: '1. Solution',
                  progress: solutionProgress,
                  isActive: solutionActive,
                  enabled: true,
                colorScheme: colorScheme,
                textTheme: textTheme,
                  onTap: () => onStepSelected(_StagePreviewMode.solution),
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(15),
                  ),
                  labelPadding: const EdgeInsets.symmetric(horizontal: 14),
                  progressPadding: const EdgeInsets.only(left: 14),
                ),
              ),
            Container(
              width: 1,
              height: double.infinity,
              color: colorScheme.outlineVariant.withValues(alpha: 0.56),
            ),
            Expanded(
                child: _StepProgressTapArea(
                  label: '2. Puzzle',
                  progress: puzzleProgress,
                  isActive: activeStep == _StagePreviewMode.puzzle,
                  enabled: canAccessPuzzleStep,
                colorScheme: colorScheme,
                textTheme: textTheme,
                  onTap: canAccessPuzzleStep
                      ? () => onStepSelected(_StagePreviewMode.puzzle)
                      : null,
                  borderRadius: const BorderRadius.horizontal(
                    right: Radius.circular(15),
                  ),
                  labelPadding: const EdgeInsets.symmetric(horizontal: 14),
                  progressPadding: const EdgeInsets.only(right: 14),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StepProgressTapArea extends StatelessWidget {
  final String label;
  final double progress;
  final bool isActive;
  final bool enabled;
  final ColorScheme colorScheme;
  final TextTheme textTheme;
  final VoidCallback? onTap;
  final BorderRadius borderRadius;
  final EdgeInsets labelPadding;
  final EdgeInsets progressPadding;

  const _StepProgressTapArea({
    required this.label,
    required this.progress,
    required this.isActive,
    required this.enabled,
    required this.colorScheme,
    required this.textTheme,
    required this.onTap,
    required this.borderRadius,
    this.labelPadding = EdgeInsets.zero,
    this.progressPadding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final activeBackground = colorScheme.brightness == Brightness.dark
        ? colorScheme.primaryContainer.withValues(alpha: 0.34)
        : colorScheme.primaryContainer.withValues(alpha: 0.92);
    final inactiveBackground = enabled
        ? colorScheme.surfaceContainerLow.withValues(alpha: 0.42)
        : colorScheme.surfaceContainerLowest.withValues(alpha: 0.22);
    final labelColor = !enabled
        ? colorScheme.onSurfaceVariant.withValues(alpha: 0.42)
        : isActive
            ? colorScheme.onPrimaryContainer
            : colorScheme.onSurfaceVariant.withValues(alpha: 0.88);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: isActive ? activeBackground : inactiveBackground,
          borderRadius: borderRadius,
        ),
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: labelPadding,
              child: Text(
                label,
                style: textTheme.labelMedium?.copyWith(
                  color: labelColor,
                  fontWeight: isActive ? FontWeight.w900 : FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: progressPadding,
              child: _StepProgressSegment(
                progress: progress,
                colorScheme: colorScheme,
                borderRadius: borderRadius,
                isActive: isActive,
              ),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}

class _StepProgressSegment extends StatelessWidget {
  final double progress;
  final ColorScheme colorScheme;
  final BorderRadius borderRadius;
  final bool isActive;

  const _StepProgressSegment({
    required this.progress,
    required this.colorScheme,
    required this.borderRadius,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    final trackColor = isActive
        ? colorScheme.onPrimaryContainer.withValues(
            alpha: colorScheme.brightness == Brightness.dark ? 0.34 : 0.18,
          )
        : colorScheme.surfaceContainerHighest;

    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox(
        height: 8,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: trackColor,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: progress.clamp(0.0, 1.0),
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WordEditorSection extends StatelessWidget {
  final WordOverlayController controller;
  final DrawingController drawingController;
  final TextEditingController solutionController;
  final ValueNotifier<String> solutionTextListenable;
  final TextEditingController creatorNameController;
  final TextEditingController promptController;
  final FocusNode generationPromptFocusNode;
  final ValueNotifier<String> promptTextListenable;
  final TextTheme textTheme;
  final ColorScheme colorScheme;
  final Color canvasBackgroundColor;
  final bool isLocked;
  final bool isLoadingInitialOverlay;
  final bool isSolutionStepComplete;
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

  const _WordEditorSection({
    required this.controller,
    required this.drawingController,
    required this.solutionController,
    required this.solutionTextListenable,
    required this.creatorNameController,
    required this.promptController,
    required this.generationPromptFocusNode,
    required this.promptTextListenable,
    required this.textTheme,
    required this.colorScheme,
    required this.canvasBackgroundColor,
    required this.isLocked,
    required this.isLoadingInitialOverlay,
    required this.isSolutionStepComplete,
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
    final compactSegmentStyle = ButtonStyle(
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
        EdgeInsets.symmetric(horizontal: 10, vertical: 0),
      ),
      textStyle: WidgetStatePropertyAll<TextStyle?>(
        textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
    );

    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        controller,
        drawingController,
        solutionTextListenable,
        promptTextListenable,
      ]),
      builder: (context, _) {
        final canGeneratePuzzleNow = !isLocked &&
            solutionTextListenable.value.trim().length >= 2 &&
            promptTextListenable.value.trim().isNotEmpty &&
            controller.hasLetters;
        final canEditDrawing = stagePreviewMode == _StagePreviewMode.solution &&
            !isLocked &&
            drawingController.hasCommittedStrokes;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                SizedBox(
                  width: 86,
                  child: Row(
                    children: <Widget>[
                      _CompactActionButton(
                        icon: Icons.undo_rounded,
                        label: 'Undo',
                        enabled: canEditDrawing,
                        onPressed: drawingController.undo,
                        dimension: 40,
                      ),
                      const SizedBox(width: 6),
                      _CompactActionButton(
                        icon: Icons.delete_outline_rounded,
                        label: 'Delete',
                        enabled: canEditDrawing,
                        onPressed: drawingController.clear,
                        dimension: 40,
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                _StageStepToggle(
                  value: stagePreviewMode,
                  canAccessPuzzleStep: isLocked || isSolutionStepComplete,
                  textTheme: textTheme,
                  onChanged: isLocked ? null : onSelectStagePreview,
                ),
              ],
            ),
            const SizedBox(height: 8),
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  stagePreviewMode == _StagePreviewMode.solution
                      ? WordOverlayStage(
                          controller: controller,
                          drawingController: drawingController,
                          isLocked: isLocked,
                          normalizePoint: normalizePoint,
                          onInteractionChanged: onStageInteractionChanged,
                          borderColor: colorScheme.outlineVariant,
                          backgroundColor: canvasBackgroundColor,
                          foregroundColor: colorScheme.onSurfaceVariant,
                        )
                      : _PuzzleStage(
                          puzzleBytes: puzzleBytes,
                          existingPreviewUrlFuture:
                              existingPuzzlePreviewUrlFuture,
                          hasStoredPuzzleImage: hasStoredPuzzleImage,
                          isGeneratingPuzzle: isGeneratingPuzzle,
                          statusText: puzzleGenerationStatus,
                          borderColor: colorScheme.outlineVariant,
                          backgroundColor: canvasBackgroundColor,
                          foregroundColor: colorScheme.onSurfaceVariant,
                          solutionBackdrop: IgnorePointer(
                            child: Opacity(
                              opacity: 0.14,
                              child: WordOverlayStage(
                                controller: controller,
                                drawingController: drawingController,
                                isLocked: true,
                                normalizePoint: null,
                                onInteractionChanged: (_) {},
                                borderColor: Colors.transparent,
                                backgroundColor: Colors.transparent,
                                foregroundColor: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                  if (isLoadingInitialOverlay)
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: canvasBackgroundColor.withValues(alpha: 0.82),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: const Center(
                        child: SizedBox.square(
                          dimension: 26,
                          child: CircularProgressIndicator.adaptive(),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (stagePreviewMode == _StagePreviewMode.solution) ...<Widget>[
              Builder(
                builder: (context) {
                  final selectedBrush = drawingController.selectedBrush;
                  final currentOpacity = drawingController.currentOpacity;
                  final currentWidth = drawingController.currentWidth;
                  final canAdjustOpacity =
                      selectedBrush != DrawingBrushType.eraser &&
                          selectedBrush != DrawingBrushType.none;
                  final canAdjustSize = selectedBrush != DrawingBrushType.none;

                  return Column(
                    children: <Widget>[
                      SizedBox(
                        height: 48,
                        child: _BrushSelectorStrip(
                          selectedBrush: selectedBrush,
                          enabled: !isLocked,
                          onSelectBrush: drawingController.selectBrush,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: _CompactSliderTile(
                              label: selectedBrush == DrawingBrushType.none
                                  ? 'Opacity'
                                  : canAdjustOpacity
                                      ? 'Opacity'
                                      : 'Eraser',
                              valueText: selectedBrush == DrawingBrushType.none
                                  ? 'Off'
                                  : canAdjustOpacity
                                      ? '${(currentOpacity * 100).round()}%'
                                      : 'On',
                              child: Opacity(
                                opacity: canAdjustOpacity ? 1 : 0.45,
                                child: SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    trackHeight: 3,
                                    thumbShape: const RoundSliderThumbShape(
                                      enabledThumbRadius: 8,
                                    ),
                                    overlayShape: const RoundSliderOverlayShape(
                                      overlayRadius: 14,
                                    ),
                                  ),
                                  child: Slider(
                                    value: currentOpacity,
                                    min: 0.2,
                                    max: 1.0,
                                    divisions: 8,
                                    onChanged: canAdjustOpacity
                                        ? drawingController.setOpacity
                                        : null,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _CompactSliderTile(
                              label: 'Size',
                              valueText: canAdjustSize
                                  ? '${(currentWidth * 1000).round()}'
                                  : 'Off',
                              child: Opacity(
                                opacity: canAdjustSize ? 1 : 0.45,
                                child: SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    trackHeight: 3,
                                    thumbShape: const RoundSliderThumbShape(
                                      enabledThumbRadius: 8,
                                    ),
                                    overlayShape: const RoundSliderOverlayShape(
                                      overlayRadius: 14,
                                    ),
                                  ),
                                  child: Slider(
                                    value: currentWidth,
                                    min: 0.006,
                                    max: 0.08,
                                    divisions: 18,
                                    onChanged: isLocked || !canAdjustSize
                                        ? null
                                        : drawingController.setBrushWidth,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: solutionController,
                enabled: !isLocked,
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                enableSuggestions: false,
                inputFormatters: <TextInputFormatter>[
                  LengthLimitingTextInputFormatter(
                      _CreateLevelScreenState._maxSolutionLength),
                ],
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: colorScheme.onSurface,
                  letterSpacing: 0.5,
                ),
                decoration: _solutionFieldDecoration(
                  colorScheme,
                  hint: 'Type the word and letters appear on the stage.',
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Letter Weight',
                style: textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              SegmentedButton<int>(
                style: compactSegmentStyle,
                segments: kWordLetterWeightOptions
                    .map(
                      (option) => ButtonSegment<int>(
                        value: option.value,
                        label: Text(option.label),
                      ),
                    )
                    .toList(growable: false),
                selected: <int>{controller.fontWeightValue},
                showSelectedIcon: false,
                onSelectionChanged: isLocked
                    ? null
                    : (selection) =>
                        controller.updateAllFontWeightValue(selection.first),
              ),
            ] else ...<Widget>[
              TextField(
                controller: promptController,
                focusNode: generationPromptFocusNode,
                enabled: !isLocked && !isGeneratingPuzzle,
                maxLines: 2,
                decoration: _sharedFieldDecoration(
                  colorScheme,
                  label: 'Puzzle Scene',
                  icon: Icons.auto_awesome_outlined,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: <Widget>[
                  SizedBox(
                    width: 54,
                    child: Text(
                      'Hard',
                      style: textTheme.labelMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(
                    child: _EditorSlider(
                      value: generationDifficulty,
                      min: 0.35,
                      max: 2.0,
                      divisions: 13,
                      onChanged: isLocked || isGeneratingPuzzle
                          ? null
                          : onGenerationDifficultyChanged,
                    ),
                  ),
                  SizedBox(
                    width: 52,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        generationDifficulty.toStringAsFixed(2),
                        style: textTheme.labelMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: isGeneratingPuzzle || !canGeneratePuzzleNow
                      ? null
                      : onGeneratePuzzle,
                  icon: Icon(
                    (puzzleBytes != null || hasStoredPuzzleImage)
                        ? Icons.refresh_rounded
                        : Icons.auto_awesome_outlined,
                  ),
                  label: Text(
                    isGeneratingPuzzle
                        ? 'Generating...'
                        : (puzzleBytes != null || hasStoredPuzzleImage)
                            ? 'Regenerate Puzzle'
                            : 'Generate Puzzle',
                  ),
                ),
              ),
              if (puzzleGenerationStatus.isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                Text(
                  puzzleGenerationStatus,
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: creatorNameController,
                enabled: !isLocked,
                textCapitalization: TextCapitalization.words,
                decoration: _sharedFieldDecoration(
                  colorScheme,
                  label: 'Creator Name',
                  icon: Icons.badge_outlined,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _WordLetterStrip extends StatefulWidget {
  final List<WordOverlayLetter> letters;
  final Map<String, WordOverlayLetter> placedById;
  final String? selectedLetterId;
  final ValueChanged<WordOverlayLetter> onSelectLetter;
  final bool enabled;

  const _WordLetterStrip({
    required this.letters,
    required this.placedById,
    required this.selectedLetterId,
    required this.onSelectLetter,
    required this.enabled,
  });

  @override
  State<_WordLetterStrip> createState() => _WordLetterStripState();
}

class _WordLetterStripState extends State<_WordLetterStrip> {
  late final ScrollController _scrollController;
  bool _showLeadingHint = false;
  bool _showTrailingHint = true;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_updateScrollHints);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateScrollHints());
  }

  @override
  void didUpdateWidget(covariant _WordLetterStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateScrollHints());
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_updateScrollHints)
      ..dispose();
    super.dispose();
  }

  void _updateScrollHints() {
    if (!mounted) {
      return;
    }

    var showLeadingHint = false;
    var showTrailingHint = false;
    if (_scrollController.hasClients) {
      final position = _scrollController.position;
      showLeadingHint = position.pixels > 4;
      showTrailingHint = position.maxScrollExtent - position.pixels > 4;
    }

    if (showLeadingHint == _showLeadingHint &&
        showTrailingHint == _showTrailingHint) {
      return;
    }

    setState(() {
      _showLeadingHint = showLeadingHint;
      _showTrailingHint = showTrailingHint;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Stack(
      children: <Widget>[
        ListView.separated(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          itemCount: widget.letters.length,
          itemBuilder: (context, index) {
            final letter = widget.letters[index];
            final placedLetter = widget.placedById[letter.id];
            return _WordLetterChip(
              letter: placedLetter ?? letter,
              isPlaced: placedLetter != null,
              selected: placedLetter != null &&
                  widget.selectedLetterId == placedLetter.id,
              enabled: widget.enabled,
              onTap: () => widget.onSelectLetter(letter),
            );
          },
          separatorBuilder: (_, __) => const SizedBox(width: 8),
        ),
        if (_showLeadingHint)
          _ScrollEdgeHint(
            alignment: Alignment.centerLeft,
            icon: Icons.chevron_left_rounded,
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            backgroundColor: colorScheme.surfaceContainerLow,
            foregroundColor: colorScheme.onSurfaceVariant,
          ),
        if (_showTrailingHint)
          _ScrollEdgeHint(
            alignment: Alignment.centerRight,
            icon: Icons.chevron_right_rounded,
            begin: Alignment.centerRight,
            end: Alignment.centerLeft,
            backgroundColor: colorScheme.surfaceContainerLow,
            foregroundColor: colorScheme.onSurfaceVariant,
          ),
      ],
    );
  }
}

class _WordLetterChip extends StatelessWidget {
  final WordOverlayLetter letter;
  final bool isPlaced;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _WordLetterChip({
    required this.letter,
    required this.isPlaced,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final backgroundColor = selected
        ? colorScheme.surface
        : isPlaced
            ? colorScheme.surfaceContainerLow
            : colorScheme.surfaceContainerLowest;
    final foregroundColor = selected
        ? colorScheme.primary
        : isPlaced
            ? colorScheme.onSurface
            : colorScheme.onSurfaceVariant;

    return Opacity(
      opacity: enabled ? 1 : 0.56,
      child: Material(
        color: backgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: selected
                ? colorScheme.secondary
                : isPlaced
                    ? colorScheme.outlineVariant
                    : colorScheme.outline,
          ),
        ),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (!isPlaced) ...<Widget>[
                    Icon(
                      Icons.add_rounded,
                      size: 14,
                      color: foregroundColor,
                    ),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    letter.letter,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: foregroundColor,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ],
              ),
            ),
          ),
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
  final VoidCallback? onTap;

  const _ModePill({
    required this.label,
    required this.icon,
    required this.selected,
    required this.enabled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final backgroundColor =
        selected ? colorScheme.surface : colorScheme.surfaceContainerLow;
    final foregroundColor =
        selected ? colorScheme.primary : colorScheme.onSurface;

    return Opacity(
      opacity: enabled ? 1 : 0.56,
      child: Material(
        color: backgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: selected ? colorScheme.primary : colorScheme.outlineVariant,
          ),
        ),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(icon, size: 16, color: foregroundColor),
                const SizedBox(width: 6),
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
      case DrawingBrushType.none:
        return Icons.pan_tool_alt_outlined;
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
        ? colorScheme.surface
        : colorScheme.surfaceContainerLow;
    final foregroundColor =
        selected ? colorScheme.primary : colorScheme.onSurface;

    return Opacity(
      opacity: enabled ? 1 : 0.54,
      child: Material(
        color: backgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color:
                selected ? colorScheme.secondary : colorScheme.outlineVariant,
          ),
        ),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            width: 104,
            height: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: <Widget>[
                Icon(_icon, size: 17, color: foregroundColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4),
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

class _BrushSelectorStrip extends StatefulWidget {
  final DrawingBrushType selectedBrush;
  final bool enabled;
  final ValueChanged<DrawingBrushType> onSelectBrush;

  const _BrushSelectorStrip({
    required this.selectedBrush,
    required this.enabled,
    required this.onSelectBrush,
  });

  @override
  State<_BrushSelectorStrip> createState() => _BrushSelectorStripState();
}

class _BrushSelectorStripState extends State<_BrushSelectorStrip> {
  late final ScrollController _scrollController;
  bool _showLeadingHint = false;
  bool _showTrailingHint = true;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_handleScrollChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateScrollHints());
  }

  @override
  void didUpdateWidget(covariant _BrushSelectorStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateScrollHints());
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScrollChanged)
      ..dispose();
    super.dispose();
  }

  void _handleScrollChanged() {
    _updateScrollHints();
  }

  void _updateScrollHints() {
    if (!mounted) {
      return;
    }

    var showLeadingHint = false;
    var showTrailingHint = false;

    if (_scrollController.hasClients) {
      final position = _scrollController.position;
      showLeadingHint = position.pixels > 4;
      showTrailingHint = position.maxScrollExtent - position.pixels > 4;
    }

    if (showLeadingHint == _showLeadingHint &&
        showTrailingHint == _showTrailingHint) {
      return;
    }

    setState(() {
      _showLeadingHint = showLeadingHint;
      _showTrailingHint = showTrailingHint;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Stack(
      children: <Widget>[
        ListView.separated(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          itemCount: DrawingBrushType.values.length,
          padding: EdgeInsets.zero,
          itemBuilder: (context, index) {
            final brush = DrawingBrushType.values[index];
            return _BrushButton(
              brush: brush,
              selected: widget.selectedBrush == brush,
              enabled: widget.enabled,
              onTap: () => widget.onSelectBrush(brush),
            );
          },
          separatorBuilder: (_, __) => const SizedBox(width: 8),
        ),
        if (_showLeadingHint)
          _ScrollEdgeHint(
            alignment: Alignment.centerLeft,
            icon: Icons.chevron_left_rounded,
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            backgroundColor: colorScheme.surfaceContainerLow,
            foregroundColor: colorScheme.onSurfaceVariant,
          ),
        if (_showTrailingHint)
          _ScrollEdgeHint(
            alignment: Alignment.centerRight,
            icon: Icons.chevron_right_rounded,
            begin: Alignment.centerRight,
            end: Alignment.centerLeft,
            backgroundColor: colorScheme.surfaceContainerLow,
            foregroundColor: colorScheme.onSurfaceVariant,
          ),
      ],
    );
  }
}

class _ScrollEdgeHint extends StatelessWidget {
  final Alignment alignment;
  final IconData icon;
  final Alignment begin;
  final Alignment end;
  final Color backgroundColor;
  final Color foregroundColor;

  const _ScrollEdgeHint({
    required this.alignment,
    required this.icon,
    required this.begin,
    required this.end,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Align(
        alignment: alignment,
        child: Container(
          width: 28,
          height: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: begin,
              end: end,
              colors: <Color>[
                backgroundColor.withValues(alpha: 0.96),
                backgroundColor.withValues(alpha: 0),
              ],
            ),
          ),
          child: Align(
            alignment: alignment,
            child: Icon(
              icon,
              size: 18,
              color: foregroundColor.withValues(alpha: 0.9),
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
  final EdgeInsetsGeometry padding;

  const _SectionCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }
}

class _EditorSlider extends StatelessWidget {
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double>? onChanged;

  const _EditorSlider({
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(
          enabledThumbRadius: 8,
        ),
        overlayShape: const RoundSliderOverlayShape(
          overlayRadius: 14,
        ),
      ),
      child: Slider(
        value: value,
        min: min,
        max: max,
        divisions: divisions,
        onChanged: onChanged,
      ),
    );
  }
}

class _CompactSliderTile extends StatelessWidget {
  final String label;
  final String valueText;
  final Widget child;

  const _CompactSliderTile({
    required this.label,
    required this.valueText,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: AutoSizeText(
                label,
                maxLines: 1,
                minFontSize: 10,
                style: textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              valueText,
              style: textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        child,
      ],
    );
  }
}

class _CompactActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onPressed;
  final double dimension;

  const _CompactActionButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onPressed,
    this.dimension = 48,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: SizedBox(
          width: dimension,
          height: dimension,
          child: FilledButton.tonal(
            onPressed: enabled ? onPressed : null,
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.padded,
              minimumSize: Size.square(dimension),
              padding: EdgeInsets.zero,
            ),
            child: Icon(icon, size: 20),
          ),
        ),
      ),
    );
  }
}

class _CreatorModesFooter extends StatelessWidget {
  final TextTheme textTheme;
  final ColorScheme colorScheme;
  final String selectedMode;
  final bool canChangeMode;
  final ValueChanged<String> onModeSelected;

  const _CreatorModesFooter({
    required this.textTheme,
    required this.colorScheme,
    required this.selectedMode,
    required this.canChangeMode,
    required this.onModeSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: _ModePill(
                label: 'Face',
                icon: Icons.face_retouching_natural_outlined,
                selected: selectedMode == UserLevelEditorMode.photoSketch,
                enabled: false,
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: _ModePill(
                label: 'Object',
                icon: Icons.draw_outlined,
                selected: selectedMode == UserLevelEditorMode.drawObject,
                enabled: canChangeMode ||
                    selectedMode == UserLevelEditorMode.drawObject,
                onTap: () => onModeSelected(UserLevelEditorMode.drawObject),
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: _ModePill(
                label: 'Word',
                icon: Icons.text_fields_outlined,
                selected: selectedMode == UserLevelEditorMode.highlight,
                enabled: canChangeMode ||
                    selectedMode == UserLevelEditorMode.highlight,
                onTap: () => onModeSelected(UserLevelEditorMode.highlight),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          canChangeMode
              ? 'Object and Word are live now. Face comes next.'
              : 'Mode is fixed while you edit this draft.',
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
