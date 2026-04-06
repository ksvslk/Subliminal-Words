import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:auto_size_text/auto_size_text.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:operation_hermes/controller/ads_controller.dart';
import 'package:operation_hermes/controller/firebase_service.dart';
import 'package:operation_hermes/controller/money_controller.dart';
import 'package:operation_hermes/data/sw_level.dart';
import 'package:operation_hermes/data/user_level_metadata.dart';
import 'package:operation_hermes/data/word_letter_style.dart';
import 'package:operation_hermes/editor/content_filter.dart';
import 'package:operation_hermes/editor/drawing_canvas.dart';
import 'package:operation_hermes/editor/face_sketch_generator.dart';
import 'package:operation_hermes/editor/generation_image_budget.dart';
import 'package:operation_hermes/editor/word_overlay_editor.dart';
import 'package:operation_hermes/ui/app_scaffold_messenger.dart';
import 'package:operation_hermes/ui/shimmer_placeholder.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';

enum _StagePreviewMode {
  solution,
  puzzle,
}

enum _CreatorErrorContext {
  facePhotoPick,
  faceSketch,
  puzzleGeneration,
  draftSave,
  reviewSubmit,
}

DrawingBrushType _brushFromName(
  String? name, {
  DrawingBrushType fallback = DrawingBrushType.none,
}) {
  return DrawingBrushType.values.firstWhere(
    (brush) => brush.name == name,
    orElse: () => fallback,
  );
}

double _normalizeStoredGenerationDifficulty(double? rawValue) {
  if (rawValue == null || !rawValue.isFinite) {
    return 5.5;
  }

  final value = rawValue.toDouble();
  if (value <= 2.0) {
    final clampedOld = value.clamp(0.1, 1.9);
    return (10.0 - ((clampedOld - 0.1) * 5.0)).clamp(1.0, 10.0);
  }

  return value.clamp(1.0, 10.0);
}

DrawingController _buildDrawingControllerFromEditorData(
  Map<dynamic, dynamic>? rawEditorData,
  {DrawingBrushType defaultBrush = DrawingBrushType.none}
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
    initialBrush: _brushFromName(
      editorData['selectedBrush'] as String?,
      fallback: defaultBrush,
    ),
    initialBrushWidths: initialBrushWidths,
    initialBrushOpacities: initialBrushOpacities,
  );
}

List<WordOverlayLetter> _extractWordLettersFromEditorData(
  Map<dynamic, dynamic>? rawEditorData,
) {
  if (rawEditorData == null) {
    return const <WordOverlayLetter>[];
  }

  final editorData = Map<String, dynamic>.from(rawEditorData);
  final rawLetters = editorData['wordLetters'] as List<dynamic>? ?? const [];
  return rawLetters.whereType<Map>().map((letterJson) {
    return WordOverlayLetter.fromJson(Map<String, dynamic>.from(letterJson));
  }).toList();
}

class CreateLevelScreen extends StatefulWidget {
  final SWLevel? initialLevel;
  final String? initialEditorMode;

  const CreateLevelScreen(
      {super.key, this.initialLevel, this.initialEditorMode});

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
  late final ValueNotifier<String> _creatorNameTextNotifier;
  late final ValueNotifier<String> _answerTextNotifier;
  late final ValueNotifier<String> _factTextNotifier;
  late final ValueNotifier<String> _generationPromptTextNotifier;
  late final ValueNotifier<bool> _drawingHasContentNotifier;
  late final ValueNotifier<bool> _wordDrawingHasContentNotifier;
  late final ValueNotifier<bool> _wordOverlayHasContentNotifier;
  late final ScrollController _editorScrollController;
  late final DrawingController _drawingController;
  late final DrawingController _wordDrawingController;
  late final WordOverlayController _wordOverlayController;
  late Future<String>? _existingPuzzlePreviewUrlFuture;
  late final ImagePicker _imagePicker;

  bool _isSaving = false;
  bool _isSubmittingForReview = false;
  bool _isGeneratingPuzzle = false;
  bool _isStageInteracting = false;
  bool _isLoadingWordEditorData = false;
  bool _isLoadingFaceEditorData = false;
  bool _isProcessingFaceSourceImage = false;
  bool _isGeneratingFaceSketch = false;
  bool _isGeneratingAfterManipulate = false;
  bool _isFaceTransformInteractionLocked = false;
  double _generationDifficulty = 5.5;
  String _puzzleGenerationStatus = '';
  Uint8List? _generatedPuzzleImageBytes;
  Uint8List? _faceSourceImageBytes;
  Uint8List? _faceSketchImageBytes;
  Size? _faceSourceImageSize;
  late _StagePreviewMode _stagePreviewMode;
  bool _hasPuzzleInvalidatedByEdit = false;
  int _lastSeenDrawingContentVersion = 0;
  int _lastSeenWordDrawingContentVersion = 0;
  int _lastSeenWordContentVersion = 0;
  int _activeGenerationToken = 0;
  String? _activePuzzleGenerationJobId;
  int _faceSketchGenerationRevision = 0;
  bool _isFaceSketchGenerationInFlight = false;
  Uint8List? _cachedPuzzleGenerationSourceImageBytes;
  String? _cachedPuzzleGenerationSourceKey;
  Timer? _puzzleSourcePrerenderDebounceTimer;
  int _puzzleSourcePrerenderToken = 0;
  String? _currentLevelId;
  late String _editorMode;
  late String _contentCategory;
  late FaceSketchSettings _faceSketchSettings;
  late FaceSourceTransform _faceSourceTransform;
  Timer? _faceSketchDebounceTimer;

  bool _forceHasStoredPuzzleImage = false;

  bool get _isLocked => widget.initialLevel?.isLocked == true;
  bool get _isEditMode => widget.initialLevel != null;
  bool get _hasStoredPuzzleImage =>
      (widget.initialLevel?.hasReviewReadyPuzzleImage == true || _forceHasStoredPuzzleImage) &&
      !_hasPuzzleInvalidatedByEdit;
  bool get _hasPuzzleImageForReview =>
      _generatedPuzzleImageBytes != null || _hasStoredPuzzleImage;
  bool get _isSolutionEditingLocked =>
      !_isLocked && _hasPuzzleImageForReview;
  bool get _hasDraftStageContent =>
      _editorMode == UserLevelEditorMode.highlight
          ? _wordOverlayController.hasLetters ||
              _wordDrawingController.hasCommittedStrokes
          : _editorMode == UserLevelEditorMode.photoSketch
              ? _faceSourceImageBytes != null
              : _drawingController.hasCommittedStrokes;
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
          : _editorMode == UserLevelEditorMode.photoSketch
              ? _faceSketchImageBytes != null
              : _drawingController.hasCommittedStrokes;
  bool get _canAccessPuzzleStep => _isLocked || _isSolutionStepComplete;
  String get _visiblePuzzleGenerationStatus =>
      _isGeneratingPuzzle ? _puzzleGenerationStatus : '';


  @override
  void initState() {
    super.initState();
    final initialLevel = widget.initialLevel;
    final initialEditorData =
        initialLevel?.editorData ?? const <String, dynamic>{};
    final initialEditorMode = widget.initialEditorMode;

    _creatorNameController =
        TextEditingController(text: initialLevel?.creatorName ?? '');
    _answerController = TextEditingController(text: initialLevel?.name ?? '');
    _factController = TextEditingController(text: initialLevel?.factHint ?? '');
    _creatorNameTextNotifier =
        ValueNotifier<String>(_creatorNameController.text);
    _answerTextNotifier = ValueNotifier<String>(_answerController.text);
    _factTextNotifier = ValueNotifier<String>(_factController.text);
    _drawingHasContentNotifier = ValueNotifier<bool>(false);
    _wordDrawingHasContentNotifier = ValueNotifier<bool>(false);
    _wordOverlayHasContentNotifier = ValueNotifier<bool>(false);
    _editorScrollController = ScrollController();
    _stagePreviewMode = widget.initialLevel?.hasReviewReadyPuzzleImage == true
        ? _StagePreviewMode.puzzle
        : _StagePreviewMode.solution;
    _editorMode = initialLevel?.editorMode ??
        (initialEditorMode != null &&
                UserLevelEditorMode.supported.contains(initialEditorMode)
            ? initialEditorMode
            : UserLevelEditorMode.drawObject);
    _contentCategory = UserLevelContentCategory.normalize(
      initialLevel?.contentCategory,
      editorMode: _editorMode,
    );
    _currentLevelId = initialLevel?.documentId;
    _generationPromptController = TextEditingController(
      text: initialEditorData['generationPrompt'] as String? ??
          initialLevel?.name ??
          '',
    );
    _generationPromptTextNotifier = ValueNotifier<String>(
      _generationPromptController.text,
    );
    _generationDifficulty = _normalizeStoredGenerationDifficulty(
      (initialEditorData['generationDifficulty'] as num?)?.toDouble(),
    );
    _faceSketchSettings = FaceSketchSettings.fromJson(
      initialEditorData['faceSketchSettings'] as Map<dynamic, dynamic>?,
    );
    _faceSourceTransform = FaceSourceTransform.fromJson(
      initialEditorData['faceSourceTransform'] as Map<dynamic, dynamic>?,
    );
    _imagePicker = ImagePicker();

    _drawingController = _buildDrawingControllerFromEditorData(
      initialEditorData,
      defaultBrush: DrawingBrushType.pencil,
    );
    _wordDrawingController = _buildDrawingControllerFromEditorData(
      initialEditorData['wordDrawing'] as Map<dynamic, dynamic>?,
      defaultBrush: DrawingBrushType.text,
    );
    _wordOverlayController = WordOverlayController(
      initialLetters: _extractWordLettersFromEditorData(initialEditorData),
    );
    _drawingHasContentNotifier.value = _drawingController.hasCommittedStrokes;
    _wordDrawingHasContentNotifier.value =
        _wordDrawingController.hasCommittedStrokes;
    _wordOverlayHasContentNotifier.value = _wordOverlayController.hasLetters;
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
    if (_editorMode == UserLevelEditorMode.photoSketch &&
        initialLevel != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadExistingFaceEditorData();
      });
    } else if (_editorMode == UserLevelEditorMode.highlight &&
        !_wordOverlayController.hasLetters &&
        (initialLevel?.solutionPath.isNotEmpty ?? false)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadExistingWordLetters();
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _schedulePuzzleSourcePrerender();
    });
  }

  @override
  void dispose() {
    _faceSketchDebounceTimer?.cancel();
    _puzzleSourcePrerenderDebounceTimer?.cancel();
    _creatorNameController.dispose();
    _answerController.dispose();
    _factController.dispose();
    _generationPromptController.dispose();
    _creatorNameTextNotifier.dispose();
    _answerTextNotifier.dispose();
    _factTextNotifier.dispose();
    _generationPromptTextNotifier.dispose();
    _drawingHasContentNotifier.dispose();
    _wordDrawingHasContentNotifier.dispose();
    _wordOverlayHasContentNotifier.dispose();
    _editorScrollController.dispose();
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
    final hasContent = _drawingController.hasCommittedStrokes;
    if (hasContent != _drawingHasContentNotifier.value) {
      _drawingHasContentNotifier.value = hasContent;
    }

    final contentVersion = _drawingController.contentVersion;
    if (contentVersion == _lastSeenDrawingContentVersion) {
      return;
    }

    _lastSeenDrawingContentVersion = contentVersion;
    _invalidatePuzzlePreview();
    _invalidatePuzzleGenerationSourceCache();
  }

  void _handleWordOverlayControllerChanged() {
    final hasContent = _wordOverlayController.hasLetters;
    if (hasContent != _wordOverlayHasContentNotifier.value) {
      _wordOverlayHasContentNotifier.value = hasContent;
    }

    final contentVersion = _wordOverlayController.contentVersion;
    if (contentVersion == _lastSeenWordContentVersion) {
      return;
    }

    _lastSeenWordContentVersion = contentVersion;
    _invalidatePuzzlePreview();
    _invalidatePuzzleGenerationSourceCache();
  }

  void _handleWordDrawingControllerChanged() {
    final hasContent = _wordDrawingController.hasCommittedStrokes;
    if (hasContent != _wordDrawingHasContentNotifier.value) {
      _wordDrawingHasContentNotifier.value = hasContent;
    }

    final contentVersion = _wordDrawingController.contentVersion;
    if (contentVersion == _lastSeenWordDrawingContentVersion) {
      return;
    }

    _lastSeenWordDrawingContentVersion = contentVersion;
    _invalidatePuzzlePreview();
    _invalidatePuzzleGenerationSourceCache();
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
      if (_wordDrawingController.selectedBrush != DrawingBrushType.text) {
        _wordDrawingController.selectBrush(DrawingBrushType.text);
      }
    }
    _invalidatePuzzlePreview();
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
  }

  void _handleGenerationPromptChanged() {
    final text = _generationPromptController.text;
    if (text == _generationPromptTextNotifier.value) {
      return;
    }
    _generationPromptTextNotifier.value = text;
    _invalidatePuzzlePreview(returnToSolutionStep: false);
  }

  void _updateGenerationDifficulty(double value) {
    if (_generationDifficulty == value) {
      return;
    }

    setState(() => _generationDifficulty = value);
    _invalidatePuzzlePreview(returnToSolutionStep: false);
  }

  void _updateContentCategory(String value) {
    final normalized = UserLevelContentCategory.normalize(
      value,
      editorMode: _editorMode,
    );
    if (_contentCategory == normalized) {
      return;
    }

    setState(() => _contentCategory = normalized);
  }

  Future<void> _pickFaceSourceImage() async {
    if (_isLocked || _isGeneratingFaceSketch) {
      return;
    }

    try {
      final pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 96,
      );
      if (pickedFile == null) {
        return;
      }

      setState(() {
        _isProcessingFaceSourceImage = true;
      });

      final normalizedBytes = await normalizeFaceSourceImage(
        await pickedFile.readAsBytes(),
      );
      final imageSize = await _decodeImageSize(normalizedBytes);

      if (!mounted) {
        return;
      }

      setState(() {
        _faceSourceImageBytes = normalizedBytes;
        _faceSourceImageSize = imageSize;
        _faceSketchImageBytes = null;
        _faceSourceTransform = const FaceSourceTransform();
        _isFaceTransformInteractionLocked = false;
        _isProcessingFaceSourceImage = false;
        _isGeneratingAfterManipulate = false;
      });
      _invalidatePuzzlePreview();
      _scheduleFaceSketchGeneration(immediate: true);
    } catch (error) {
      _showFriendlyError(error, context: _CreatorErrorContext.facePhotoPick);
    }
  }

  void _updateFaceSketchSettings(FaceSketchSettings settings) {
    if (_isLocked) {
      return;
    }

    setState(() => _faceSketchSettings = settings);
    _invalidatePuzzlePreview();
    _scheduleFaceSketchGeneration();
  }

  void _updateFaceSourceTransform(FaceSourceTransform transform) {
    if (_isLocked || _faceSourceImageBytes == null) {
      return;
    }

    setState(() => _faceSourceTransform = _sanitizedFaceTransform(transform));
  }

  void _discardFaceSourceImage() {
    if (_isLocked || _faceSourceImageBytes == null) {
      return;
    }

    _cancelPendingFaceSketchGeneration();
    _handleStageInteractionChanged(false);
    setState(() {
      _faceSourceImageBytes = null;
      _faceSourceImageSize = null;
      _faceSketchImageBytes = null;
      _faceSourceTransform = const FaceSourceTransform();
      _isFaceTransformInteractionLocked = false;
      _isGeneratingFaceSketch = false;
      _isGeneratingAfterManipulate = false;
      _stagePreviewMode = _StagePreviewMode.solution;
    });
    _invalidatePuzzlePreview();
  }

  Future<void> _confirmDiscardFaceSourceImage() async {
    if (_isLocked || _faceSourceImageBytes == null) {
      return;
    }

    final shouldDiscard = await showDialog<bool>(
          context: context,
        builder: (context) => AlertDialog(
            title: const Text('Discard photo?'),
            content: const Text(
              'This will remove the current photo, sketch, and framing so you can start again.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Discard'),
              ),
            ],
          ),
        ) ??
        false;

    if (!mounted || !shouldDiscard) {
      return;
    }

    _discardFaceSourceImage();
  }

  void _resetFaceSourceTransform() {
    if (_isLocked || _faceSourceImageBytes == null) {
      return;
    }

    setState(() => _faceSourceTransform = const FaceSourceTransform());
    _invalidatePuzzlePreview();
    _scheduleFaceSketchGeneration(immediate: true);
  }

  void _toggleFaceTransformInteractionLock() {
    if (_isLocked || _faceSourceImageBytes == null || _isGeneratingFaceSketch) {
      return;
    }

    _handleStageInteractionChanged(false);
    setState(() {
      _isFaceTransformInteractionLocked = !_isFaceTransformInteractionLocked;
    });
  }

  void _finishFaceSourceTransform() {
    if (_isLocked || _faceSourceImageBytes == null) {
      return;
    }

    _invalidatePuzzlePreview();
    setState(() => _isGeneratingAfterManipulate = true);
    _scheduleFaceSketchGeneration(immediate: true);
  }

  void _scheduleFaceSketchGeneration({bool immediate = false}) {
    _faceSketchGenerationRevision += 1;
    _faceSketchDebounceTimer?.cancel();
    if (_faceSourceImageBytes == null) {
      return;
    }

    if (immediate) {
      unawaited(_generateFaceSketchPreview());
      return;
    }

    _faceSketchDebounceTimer = Timer(
      const Duration(milliseconds: 140),
      () => unawaited(_generateFaceSketchPreview()),
    );
  }

  void _cancelPendingFaceSketchGeneration() {
    _faceSketchDebounceTimer?.cancel();
    _faceSketchGenerationRevision += 1;
  }

  Future<void> _generateFaceSketchPreview() async {
    if (_isFaceSketchGenerationInFlight) {
      return;
    }

    final sourceBytes = _faceSourceImageBytes;
    if (sourceBytes == null) {
      return;
    }

    final requestedRevision = _faceSketchGenerationRevision;
    final settings = _faceSketchSettings;
    final transform = _sanitizedFaceTransform(_faceSourceTransform);
    _isFaceSketchGenerationInFlight = true;
    var shouldGenerateLatest = false;
    if (mounted) {
      setState(() => _isGeneratingFaceSketch = true);
    }

    try {
      final sketchPngBytes = await generateFaceSketchPng(
        sourceBytes: sourceBytes,
        settings: settings,
        transform: transform,
      );
      final sketchBytes = await compressFaceSketchWebp(sketchPngBytes);
      final hasNewerRequest =
          requestedRevision != _faceSketchGenerationRevision ||
          _faceSourceImageBytes == null;
      if (mounted && !hasNewerRequest) {
        setState(() {
          _faceSketchImageBytes = sketchBytes;
          _isGeneratingFaceSketch = false;
          _isGeneratingAfterManipulate = false;
        });
      }
    } catch (error) {
      final hasNewerRequest =
          requestedRevision != _faceSketchGenerationRevision ||
          _faceSourceImageBytes == null;
      if (mounted && !hasNewerRequest) {
        setState(() {
          _isGeneratingFaceSketch = false;
          _isGeneratingAfterManipulate = false;
        });
        _showFriendlyError(error, context: _CreatorErrorContext.faceSketch);
      }
    } finally {
      _isFaceSketchGenerationInFlight = false;
      shouldGenerateLatest = mounted &&
          _faceSourceImageBytes != null &&
          requestedRevision != _faceSketchGenerationRevision;
    }

    if (shouldGenerateLatest) {
      unawaited(_generateFaceSketchPreview());
    }
  }

  Future<Uint8List?> _loadStorageBytes(String storagePath) async {
    if (storagePath.isEmpty) {
      return null;
    }

    final firebaseService = context.read<FirebaseService>();
    return firebaseService.getStorageBytes(storagePath);
  }

  Future<Size?> _decodeImageSize(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final size = Size(image.width.toDouble(), image.height.toDouble());
    image.dispose();
    codec.dispose();
    return size;
  }

  Future<void> _loadExistingFaceEditorData() async {
    final initialLevel = widget.initialLevel;
    if (initialLevel == null ||
        _editorMode != UserLevelEditorMode.photoSketch) {
      return;
    }

    final editorData = initialLevel.editorData;
    final sourceImagePath =
        (editorData['sourceImagePath'] ?? '').toString().trim();

    if (mounted) {
      setState(() => _isLoadingFaceEditorData = true);
    }

    try {
      Uint8List? sourceBytes;
      if (sourceImagePath.isNotEmpty) {
        try {
          sourceBytes = await _loadStorageBytes(sourceImagePath);
        } catch (_) {
          // Source image might have expired/been deleted.
        }
      }
      
      final sourceSize =
          sourceBytes == null ? null : await _decodeImageSize(sourceBytes);
      final loadedTransform = FaceSourceTransform.fromJson(
        editorData['faceSourceTransform'] as Map<dynamic, dynamic>?,
      );
      final clampedTransform = sourceSize == null
          ? loadedTransform
          : sanitizeFaceTransform(transform: loadedTransform);
      Uint8List? sketchBytes;
      if (sourceBytes != null) {
        try {
          final regeneratedSketchPng = await generateFaceSketchPng(
            sourceBytes: sourceBytes,
            settings: _faceSketchSettings,
            transform: clampedTransform,
          );
          sketchBytes = await compressFaceSketchWebp(regeneratedSketchPng);
        } catch (_) {
          if (initialLevel.solutionPath.isNotEmpty) {
            try {
              sketchBytes = await _loadStorageBytes(initialLevel.solutionPath);
            } catch (_) {}
          }
        }
      } else if (initialLevel.solutionPath.isNotEmpty) {
        try {
          sketchBytes = await _loadStorageBytes(initialLevel.solutionPath);
        } catch (_) {}
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _faceSourceImageBytes = sourceBytes;
        _faceSourceImageSize = sourceSize;
        _faceSketchImageBytes = sketchBytes;
        _faceSourceTransform = clampedTransform;
        if (!_isGeneratingPuzzle && _hasStoredPuzzleImage) {
          _puzzleGenerationStatus = '';
        }
      });
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() => _isLoadingFaceEditorData = false);
      }
    }
  }

  String? _puzzleGenerationSourceCacheKey() {
    if (_editorMode == UserLevelEditorMode.highlight) {
      return 'word:${_wordOverlayController.contentVersion}:${_wordDrawingController.contentVersion}';
    }

    if (_editorMode == UserLevelEditorMode.drawObject) {
      return 'draw:${_drawingController.contentVersion}';
    }

    return null;
  }

  void _invalidatePuzzleGenerationSourceCache() {
    _puzzleSourcePrerenderDebounceTimer?.cancel();
    _puzzleSourcePrerenderToken += 1;
    _cachedPuzzleGenerationSourceImageBytes = null;
    _cachedPuzzleGenerationSourceKey = null;
    _schedulePuzzleSourcePrerender();
  }

  void _schedulePuzzleSourcePrerender({
    Duration delay = const Duration(milliseconds: 260),
  }) {
    final cacheKey = _puzzleGenerationSourceCacheKey();
    if (cacheKey == null ||
        !_hasSolutionStageContent ||
        _isStageInteracting ||
        _isGeneratingPuzzle ||
        _isSaving ||
        _isSubmittingForReview) {
      return;
    }

    if (_cachedPuzzleGenerationSourceKey == cacheKey &&
        _cachedPuzzleGenerationSourceImageBytes != null) {
      return;
    }

    _puzzleSourcePrerenderDebounceTimer?.cancel();
    final token = ++_puzzleSourcePrerenderToken;
    _puzzleSourcePrerenderDebounceTimer = Timer(
      delay,
      () => unawaited(
        _preparePuzzleGenerationSourceCache(
          expectedCacheKey: cacheKey,
          token: token,
        ),
      ),
    );
  }

  Future<void> _preparePuzzleGenerationSourceCache({
    required String expectedCacheKey,
    required int token,
  }) async {
    if (!mounted ||
        _isStageInteracting ||
        _isGeneratingPuzzle ||
        _isSaving ||
        _isSubmittingForReview) {
      return;
    }

    if (_puzzleGenerationSourceCacheKey() != expectedCacheKey) {
      return;
    }

    try {
      final sourceBytes = await _buildPuzzleGenerationSourceImage();
      if (!mounted ||
          token != _puzzleSourcePrerenderToken ||
          _puzzleGenerationSourceCacheKey() != expectedCacheKey) {
        return;
      }

      _cachedPuzzleGenerationSourceImageBytes = sourceBytes;
      _cachedPuzzleGenerationSourceKey = expectedCacheKey;
    } catch (_) {
      // Pre-render caching is a best-effort optimization only.
    }
  }

  void _invalidatePuzzlePreview({bool returnToSolutionStep = true}) {

    if (_generatedPuzzleImageBytes == null && !_hasStoredPuzzleImage) {
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _generatedPuzzleImageBytes = null;
      _hasPuzzleInvalidatedByEdit = true;
      if (returnToSolutionStep) {
        _stagePreviewMode = _StagePreviewMode.solution;
      }
      if (!_isGeneratingPuzzle) {
        _puzzleGenerationStatus = '';
      }
    });
  }

  Future<bool> _confirmRegeneratePuzzle() async {
    if (!_hasPuzzleImageForReview || _hasPuzzleInvalidatedByEdit || !mounted) {
      return true;
    }

    final shouldRegenerate = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Generate a new puzzle?'),
            content: const Text(
              'This will replace the current puzzle. Your current work will be saved first so you can keep going safely.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Regenerate'),
              ),
            ],
          ),
        ) ??
        false;

    return shouldRegenerate;
  }

  Future<void> _confirmUnlockSolutionEditing() async {
    if (!_isSolutionEditingLocked || !mounted) {
      return;
    }

    final shouldClearPuzzle = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Edit solution?'),
            content: const Text(
              'Editing the solution will clear the current puzzle and you will need to generate it again.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Edit Solution'),
              ),
            ],
          ),
        ) ??
        false;

    if (!mounted || !shouldClearPuzzle) {
      return;
    }

    _invalidatePuzzlePreview();
  }



  FaceSourceTransform _sanitizedFaceTransform(FaceSourceTransform transform) {
    return sanitizeFaceTransform(transform: transform);
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
      final editorDataLetters =
          _extractWordLettersFromEditorData(initialLevel.editorData);
      if (editorDataLetters.isNotEmpty) {
        _wordOverlayController.replaceLetters(editorDataLetters);
        _lastSeenWordContentVersion = _wordOverlayController.contentVersion;
        _schedulePuzzleSourcePrerender();
        return;
      }

      final firebaseService = context.read<FirebaseService>();
      final svgBytes =
          await firebaseService.getStorageBytes(initialLevel.solutionPath);
      if (svgBytes == null || svgBytes.isEmpty) {
        return;
      }

      final letters = parseWordOverlayLetters(utf8.decode(svgBytes));
      if (!mounted || letters.isEmpty) {
        return;
      }

      _wordOverlayController.replaceLetters(letters);
      _lastSeenWordContentVersion = _wordOverlayController.contentVersion;
      _schedulePuzzleSourcePrerender();
    } catch (_) {
      // If the existing overlay cannot be parsed, the editor can still rebuild it.
    } finally {
      if (mounted) {
        setState(() => _isLoadingWordEditorData = false);
      }
    }
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

  void _selectStagePreview(_StagePreviewMode mode) {
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
      return;
    }

    setState(() => _stagePreviewMode = mode);
  }

  bool _isPuzzleGenerationRequestCancelled(int generationToken) {
    return generationToken != _activeGenerationToken;
  }

  Future<void> _bestEffortCancelPuzzleGeneration(String jobId) async {
    try {
      await context.read<FirebaseService>().cancelPuzzleGeneration(jobId);
    } catch (_) {
      // Local cancel is still valuable even if the remote job can't be stopped.
    }
  }

  void _cancelPuzzleGeneration() {
    if (!_isGeneratingPuzzle || !mounted) {
      return;
    }

    final activeJobId = _activePuzzleGenerationJobId?.trim();
    setState(() {
      _activeGenerationToken += 1;
      _isGeneratingPuzzle = false;
      _puzzleGenerationStatus = '';
      _activePuzzleGenerationJobId = null;
      _stagePreviewMode = _StagePreviewMode.puzzle;
    });

    _showSnack('Puzzle generation cancelled.');
    if (activeJobId != null && activeJobId.isNotEmpty) {
      unawaited(_bestEffortCancelPuzzleGeneration(activeJobId));
    }
  }

  Future<void> _generatePuzzle({
    bool skipExistingPuzzleConfirmation = false,
  }) async {
    if (_isLocked) {
      _showSnack('Submitted levels are locked and can no longer be edited.');
      return;
    }

    if (_isGeneratingPuzzle) {
      _showSnack('Puzzle generation is already running.');
      return;
    }

    if (_isSaving) {
      if (_isSaving) {
        _showSnack('Wait for the level to finish saving first.');
      }
      return;
    }

    if (!mounted) {
      return;
    }

    final prompt = _generationPromptController.text.trim();
    final validationMessage = _validateGenerationInputs();
    if (validationMessage != null) {
      _showSnack(validationMessage);
      return;
    }

    if (!skipExistingPuzzleConfirmation &&
        !await _confirmRegeneratePuzzle()) {
      return;
    }

    for (final value in <String>[prompt]) {
      if (ContentFilter.containsBlockedTerm(value)) {
        _showSnack('Please remove profanity before generating.');
        return;
      }
    }

    if (!mounted) {
      return;
    }

    FocusScope.of(context).unfocus();
    _handleStageInteractionChanged(false);
    final firebaseService = context.read<FirebaseService>();
    final generationToken = ++_activeGenerationToken;

    setState(() {
      _isGeneratingPuzzle = true;
      _puzzleGenerationStatus = 'Saving';
      _activePuzzleGenerationJobId = null;
      _stagePreviewMode = _StagePreviewMode.puzzle;
    });

    try {
      final levelId = await _persistCurrentLevel(
        firebaseService: firebaseService,
        includeFaceSolutionAsset: false,
      );
      if (!mounted || _isPuzzleGenerationRequestCancelled(generationToken)) {
        return;
      }

      setState(() => _puzzleGenerationStatus = 'Preparing');
      final sourceCacheKey = _puzzleGenerationSourceCacheKey();
      final sourceImageBytes = sourceCacheKey != null &&
              _cachedPuzzleGenerationSourceKey == sourceCacheKey &&
              _cachedPuzzleGenerationSourceImageBytes != null
          ? _cachedPuzzleGenerationSourceImageBytes!
          : await _buildPuzzleGenerationSourceImage();
      if (sourceCacheKey != null) {
        _cachedPuzzleGenerationSourceKey = sourceCacheKey;
        _cachedPuzzleGenerationSourceImageBytes = sourceImageBytes;
      }
      await _runPuzzleGenerationWithAdaptiveCompression(
        firebaseService: firebaseService,
        generationToken: generationToken,
        sourceImageBytes: sourceImageBytes,
        prompt: prompt,
        levelId: levelId,
        onJobStarted: (jobId) async {
          if (!mounted ||
              _isPuzzleGenerationRequestCancelled(generationToken)) {
            return;
          }
          setState(() => _activePuzzleGenerationJobId = jobId);
        },
      );

      if (!mounted || _isPuzzleGenerationRequestCancelled(generationToken)) {
        return;
      }

      if (mounted) {
        setState(() => _puzzleGenerationStatus = 'Generating\nSafe to leave.');
      }
      
      int pollCount = 0;
      bool hasSeenActiveJob = false;

      while (mounted && !_isPuzzleGenerationRequestCancelled(generationToken)) {
        await Future<void>.delayed(const Duration(seconds: 4));
        if (!mounted || _isPuzzleGenerationRequestCancelled(generationToken)) {
          break;
        }
        pollCount++;

        try {
          final levelData = await firebaseService.getMyLevel(levelId);
          if (levelData != null) {
            final activeCloudJobId = levelData.pendingPuzzleGenerationJobId;

            if (_activePuzzleGenerationJobId != null && activeCloudJobId == _activePuzzleGenerationJobId) {
              hasSeenActiveJob = true;
              
              final backendStatus = '${levelData.pendingPuzzleGeneration?['status'] ?? ''}'.trim().toLowerCase();
              if (backendStatus == 'error' || backendStatus == 'failed') {
                 break;
              }
              if (backendStatus == 'completed' || backendStatus == 'success') {
                 setState(() { 
                   _forceHasStoredPuzzleImage = true;
                   _hasPuzzleInvalidatedByEdit = false;
                   if (levelData.hasReviewReadyPuzzleImage) {
                     _existingPuzzlePreviewUrlFuture = firebaseService.getDownloadUrl(levelData.puzzlePath);
                   }
                   _puzzleGenerationStatus = 'Finished!';
                 });
                 break;
              }
              continue;
            }

            if (hasSeenActiveJob && activeCloudJobId != _activePuzzleGenerationJobId) {
              if (activeCloudJobId != null && activeCloudJobId.isNotEmpty) {
                // The backend autonomously spawned a retry job! Re-latch onto the new job ID.
                _activePuzzleGenerationJobId = activeCloudJobId;
                continue;
              }

              if (levelData.hasReviewReadyPuzzleImage) {
                setState(() {
                  _forceHasStoredPuzzleImage = true;
                  _hasPuzzleInvalidatedByEdit = false;
                  _existingPuzzlePreviewUrlFuture = firebaseService.getDownloadUrl(levelData.puzzlePath);
                  _puzzleGenerationStatus = 'Finished!';
                });
              }
              break;
            }

            if (pollCount > 12) {
              setState(() { 
                _forceHasStoredPuzzleImage = true;
                if (levelData.hasReviewReadyPuzzleImage) {
                   _hasPuzzleInvalidatedByEdit = false;
                   _existingPuzzlePreviewUrlFuture = firebaseService.getDownloadUrl(levelData.puzzlePath);
                }
              });
              break;
            }
          }
        } catch (_) {
          // Ignore network errors and continue polling
        }
      }

      if (_forceHasStoredPuzzleImage || _hasStoredPuzzleImage || _isPuzzleGenerationRequestCancelled(generationToken)) {
        return;
      }
      throw StateError('The puzzle generation ended prematurely or failed silently on the backend.');
    } on PuzzleGenerationCancelledException {
      return;
    } catch (error) {
      if (!mounted) {
        return;
      }
      final friendlyMessage = _friendlyErrorMessage(
        error,
        context: _CreatorErrorContext.puzzleGeneration,
      );
      setState(() {
        _stagePreviewMode = _StagePreviewMode.puzzle;
        _puzzleGenerationStatus = friendlyMessage;
      });
      _showFriendlyError(
        error,
        context: _CreatorErrorContext.puzzleGeneration,
      );
    } finally {
      if (mounted && generationToken == _activeGenerationToken) {
        _handleStageInteractionChanged(false);
        setState(() {
          _isGeneratingPuzzle = false;
          _activePuzzleGenerationJobId = null;
        });
      }
    }
  }

  Future<Uint8List> _buildPuzzleGenerationSourceImage() async {
    if (_editorMode == UserLevelEditorMode.highlight) {
      return exportWordOverlayAsPng(
        letters: _wordOverlayController.letters,
        strokes: _wordDrawingController.strokes,
        backgroundColor: _generationExportBackground,
      );
    }

    if (_editorMode == UserLevelEditorMode.photoSketch) {
      return generateHighFidelityFaceSketchSquare(
        sourceBytes: _faceSourceImageBytes!,
        settings: _faceSketchSettings,
        transform: _sanitizedFaceTransform(_faceSourceTransform),
      );
    }

    return exportDrawingAsPng(
      strokes: _drawingController.strokes,
      backgroundColor: _generationExportBackground,
    );
  }

  Future<void> _runPuzzleGenerationWithAdaptiveCompression({
    required FirebaseService firebaseService,
    required int generationToken,
    required Uint8List sourceImageBytes,
    required String prompt,
    required String levelId,
    required Future<void> Function(String jobId) onJobStarted,
  }) async {
    const controlDimensions = <int>[1024, 896, 768, 640, 512];
    Object? lastError;

    for (var i = 0; i < controlDimensions.length; i += 1) {
      if (_isPuzzleGenerationRequestCancelled(generationToken)) {
        throw const PuzzleGenerationCancelledException();
      }
      if (mounted && generationToken == _activeGenerationToken) {
        setState(() {
          _puzzleGenerationStatus = i == 0
              ? 'Preparing puzzle'
              : 'Preparing a lighter image';
        });
      }

      final solutionBytes = await buildGenerationControlJpeg(
        sourceImageBytes,
        dimension: controlDimensions[i],
        failureLabel: switch (_editorMode) {
          UserLevelEditorMode.highlight => 'word solution image',
          UserLevelEditorMode.photoSketch => 'photo solution projection',
          _ => 'object solution image',
        },
      );
      if (_isPuzzleGenerationRequestCancelled(generationToken)) {
        throw const PuzzleGenerationCancelledException();
      }

      try {
        await firebaseService.startDrawObjectPuzzleGeneration(
          solutionImageBytes: solutionBytes,
          solutionFileName: '1.jpg',
          solutionMimeType: 'image/jpeg',
          prompt: prompt,
          difficulty: double.parse((1.8 - ((_generationDifficulty - 1.0) * (1.4 / 9.0))).toStringAsFixed(2)),
          levelId: levelId,
          shouldCancel: () => _isPuzzleGenerationRequestCancelled(generationToken),
          onJobStarted: onJobStarted,
          onStatusChanged: (status) {
            if (!mounted || generationToken != _activeGenerationToken) {
              return;
            }
            setState(() => _puzzleGenerationStatus = status);
          },
        );
        return;
      } catch (error) {
        lastError = error;
        if (!_shouldRetryPuzzleGenerationWithSmallerImage(error) ||
            i == controlDimensions.length - 1) {
          rethrow;
        }
      }
    }

    throw lastError ?? StateError('Could not generate the puzzle right now.');
  }

  bool _shouldRetryPuzzleGenerationWithSmallerImage(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('too large') ||
        message.contains('(413)') ||
        message.contains('payload') ||
        message.contains('too detailed') ||
        message.contains('solution image');
  }

  String? _validateGenerationInputs() {
    final solution = _answerController.text.trim();
    final prompt = _generationPromptController.text.trim();

    if (_editorMode == UserLevelEditorMode.photoSketch &&
        _isGeneratingFaceSketch) {
      return 'Wait for the face sketch to finish updating.';
    }

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
    } else if (_editorMode == UserLevelEditorMode.photoSketch) {
      if (_faceSketchImageBytes == null) {
        return 'Add a photo before generating.';
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

    if (!forSubmission) {
      if (_editorMode == UserLevelEditorMode.highlight) {
        if (!_hasDraftStageContent) {
          return 'Add letters or drawing to the stage before saving a draft.';
        }
      } else if (_editorMode == UserLevelEditorMode.photoSketch) {
        if (_faceSourceImageBytes == null) {
          return 'Add a photo before saving a draft.';
        }
      } else if (!_drawingController.hasCommittedStrokes) {
        return 'Draw something before saving a draft.';
      }

      return null;
    }

    if (_editorMode == UserLevelEditorMode.photoSketch &&
        _isGeneratingFaceSketch) {
      return 'Wait for the photo sketch to finish updating before saving.';
    }

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
    } else if (_editorMode == UserLevelEditorMode.photoSketch) {
      if (_faceSourceImageBytes == null || _faceSketchImageBytes == null) {
        return 'Add a photo before saving.';
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

  Future<String> _persistCurrentLevel({
    required FirebaseService firebaseService,
    required bool includeFaceSolutionAsset,
    Uint8List? puzzleImageBytesOverride,
  }) async {
    late final String levelId;
    final puzzleImageBytes = puzzleImageBytesOverride ?? _generatedPuzzleImageBytes;
    final allowReuseExistingPuzzle =
        puzzleImageBytes == null && !_hasPuzzleInvalidatedByEdit;

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
        levelId: _currentLevelId,
        creatorName: _creatorNameController.text,
        answer: _answerController.text,
        factText: '',
        contentCategory: _contentCategory,
        solutionSvg: generateWordOverlaySvg(_wordOverlayController.letters),
        puzzleImageBytes: puzzleImageBytes,
        allowReuseExistingPuzzle: allowReuseExistingPuzzle,
        editorData: editorData,
      );
    } else if (_editorMode == UserLevelEditorMode.photoSketch) {
      final clampedTransform = _sanitizedFaceTransform(_faceSourceTransform);
      final editorData = <String, dynamic>{
        'faceSketchSettings': _faceSketchSettings.toJson(),
        'faceSourceTransform': clampedTransform.toJson(),
        'generationPrompt': _generationPromptController.text.trim(),
        'generationDifficulty': _generationDifficulty,
      };
      final solutionImageBytes = includeFaceSolutionAsset
          ? await compressFaceSketchWebp(
              await generateFaceSketchPng(
                sourceBytes: _faceSourceImageBytes!,
                settings: _faceSketchSettings,
                transform: clampedTransform,
              ),
            )
          : null;

      levelId = await firebaseService.savePhotoSketchLevel(
        levelId: _currentLevelId,
        creatorName: _creatorNameController.text,
        answer: _answerController.text,
        factText: _factController.text,
        contentCategory: _contentCategory,
        sourceImageBytes: _faceSourceImageBytes!,
        solutionImageBytes: solutionImageBytes,
        puzzleImageBytes: puzzleImageBytes,
        allowReuseExistingPuzzle: allowReuseExistingPuzzle,
        persistSolutionAsset: includeFaceSolutionAsset,
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
        levelId: _currentLevelId,
        creatorName: _creatorNameController.text,
        answer: _answerController.text,
        factText: _factController.text,
        contentCategory: _contentCategory,
        solutionPngBytes: pngBytes,
        puzzleImageBytes: puzzleImageBytes,
        allowReuseExistingPuzzle: allowReuseExistingPuzzle,
        editorData: editorData,
      );
    }

    if (mounted && _currentLevelId != levelId) {
      setState(() => _currentLevelId = levelId);
    }

    return levelId;
  }

  Future<void> _save({required bool submitAfterSave}) async {
    if (_isLocked) {
      _showSnack('Submitted levels are locked and can no longer be edited.');
      return;
    }

    if (_isSaving) {
      _showSnack('This level is already saving.');
      return;
    }

    if (_isGeneratingPuzzle) {
      _showSnack('Wait for puzzle generation to finish before saving.');
      return;
    }

    final validationMessage = _validateInputs(forSubmission: submitAfterSave);
    if (validationMessage != null) {
      _showSnack(validationMessage);
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _isSaving = true;
      _isSubmittingForReview = submitAfterSave;
    });
    final firebaseService = context.read<FirebaseService>();

    try {
      final levelId = await _persistCurrentLevel(
        firebaseService: firebaseService,
        includeFaceSolutionAsset: submitAfterSave,
      );

      if (submitAfterSave) {
        await firebaseService.submitUserLevelForReview(levelId);
      }

      if (!mounted) {
        return;
      }

      if (submitAfterSave) {
        Navigator.of(context).pop(true);
        return;
      }
      _showSnack('Draft saved.');
    } catch (error) {
      _showFriendlyError(
        error,
        context: submitAfterSave
            ? _CreatorErrorContext.reviewSubmit
            : _CreatorErrorContext.draftSave,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _isSubmittingForReview = false;
        });
      }
    }
  }

  void _showFriendlyError(
    Object error, {
    required _CreatorErrorContext context,
  }) {
    _showSnack(_friendlyErrorMessage(error, context: context));
  }

  String _friendlyErrorMessage(
    Object error, {
    required _CreatorErrorContext context,
  }) {
    final rawMessage = error
        .toString()
        .replaceFirst('Exception: ', '')
        .replaceFirst('Bad state: ', '')
        .trim();
    final message = rawMessage.toLowerCase();

    final isWarmupDelay = message.contains('warming up') ||
        message.contains('taking longer than usual to start') ||
        message.contains('still starting up') ||
        message.contains('starting handler') ||
        message.contains('starting server') ||
        message.contains('loading model') ||
        message.contains('initializing') ||
        message.contains('boot');
    final isNetworkIssue = message.contains('network') ||
        message.contains('connection') ||
        message.contains('timed out') ||
        message.contains('timeout') ||
        message.contains('temporarily unavailable') ||
        message.contains('service unavailable') ||
        message.contains('internal server error') ||
        message.contains('(500)') ||
        message.contains('(502)') ||
        message.contains('(503)') ||
        message.contains('(504)');
    final isAuthIssue = message.contains('signed in') ||
        message.contains('app check') ||
        message.contains('unauth') ||
        message.contains('permission') ||
        message.contains('forbidden');
    final isTooLarge = message.contains('too large') ||
        message.contains('(413)');
    final isUnsupportedUpload = message.contains('only jpg, png, or webp') ||
        message.contains('unsupported upload kind') ||
        message.contains('unsupported image');
    final isUnsafeImage = message.contains('too explicit') ||
        message.contains('adult') ||
        message.contains('racy') ||
        message.contains('violence');
    final isUnreadableImage = message.contains('could not read that face photo') ||
        message.contains('could not read that photo') ||
        message.contains('invalid source image') ||
        message.contains('valid solution image');

    switch (context) {
      case _CreatorErrorContext.facePhotoPick:
        if (message.contains('permission')) {
          return 'Please allow photo access to add a photo.';
        }
        if (isTooLarge) {
          return 'That photo is too large. Please choose a smaller one.';
        }
        return 'Could not open that photo. Please try a different image.';

      case _CreatorErrorContext.faceSketch:
        if (message.contains('level creation is unavailable')) {
          return 'Level creation is unavailable for this account right now.';
        }
        if (isTooLarge) {
          return 'That photo is too detailed right now. Try a smaller or simpler image.';
        }
        return 'Could not update the photo sketch right now. Please try again.';

      case _CreatorErrorContext.puzzleGeneration:
        if (message.contains('level creation is unavailable')) {
          return 'Level creation is unavailable for this account right now.';
        }
        if (message.contains('today\'s puzzle generation limit')) {
          return 'You have reached today\'s puzzle generation limit. Please try again tomorrow.';
        }
        if (message.contains('another puzzle generation is already running')) {
          return 'Wait for your current puzzle generation to finish first.';
        }
        if (message.contains('please wait a moment before starting another puzzle')) {
          return 'Please wait a moment before starting another puzzle.';
        }
        if (isWarmupDelay) {
          return 'Puzzle generation is taking longer than usual. Please keep this screen open and try again in a moment.';
        }
        if (isTooLarge) {
          return 'This puzzle image is still too detailed right now. Try a simpler image or scene.';
        }
        if (isAuthIssue) {
          return 'The puzzle generator is still getting ready. Please keep this screen open and try again in a moment.';
        }
        if (isNetworkIssue) {
          return 'The connection to the puzzle generator was interrupted. Please keep this screen open and try again.';
        }
        return 'Could not generate the puzzle right now. Please try again.';

      case _CreatorErrorContext.draftSave:
        if (message.contains('level creation is unavailable')) {
          return 'Level creation is unavailable for this account right now.';
        }
        if (isUnsupportedUpload) {
          return 'Only JPG, PNG, or WebP photos are allowed.';
        }
        if (isUnsafeImage) {
          return 'That photo looks too explicit for Subliminal Words. Please choose a different image.';
        }
        if (isUnreadableImage) {
          return 'Could not read that photo. Please choose a different image.';
        }
        if (isAuthIssue) {
          return 'Could not save this level right now. Please reopen Subliminal Words and try again.';
        }
        if (isNetworkIssue) {
          return 'Could not save this level right now. Check your connection and try again.';
        }
        return 'Could not save this level right now. Please try again.';

      case _CreatorErrorContext.reviewSubmit:
        if (message.contains('level creation is unavailable')) {
          return 'Level creation is unavailable for this account right now.';
        }
        if (message.contains('safety-checked before review')) {
          return 'Save this photo level again before submitting it for review.';
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
        if (isUnsupportedUpload) {
          return 'Only JPG, PNG, or WebP photos are allowed.';
        }
        if (isUnsafeImage) {
          return 'That photo looks too explicit for Subliminal Words. Please choose a different image.';
        }
        if (isUnreadableImage) {
          return 'Could not read that photo. Please choose a different image.';
        }
        if (isAuthIssue) {
          return 'Could not submit this level right now. Please reopen Subliminal Words and try again.';
        }
        if (isNetworkIssue) {
          return 'Could not submit this level right now. Check your connection and try again.';
        }
        return 'Could not submit this level for review right now. Please try again.';
    }
  }

  void _showSnack(String message) {
    showAppSnackBar(message);
  }

  void _handleStageInteractionChanged(bool isInteracting) {
    if (_isStageInteracting == isInteracting || !mounted) {
      return;
    }

    setState(() => _isStageInteracting = isInteracting);
    if (!isInteracting) {
      _schedulePuzzleSourcePrerender();
    }
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
    final isLevelMutationLocked = _isSaving;
    final areMutationControlsLocked = _isSaving || _isGeneratingPuzzle;
    const double bodyBottomPadding = 24.0;
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
      child: PopScope(
        canPop: !isLevelMutationLocked,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) {
            return;
          }

          if (isLevelMutationLocked) {
            _showSnack('Please wait for this level to finish saving.');
            return;
          }
        },
        child: Scaffold(
          resizeToAvoidBottomInset: false,
          backgroundColor: colorScheme.surface,
          appBar: AppBar(
            backgroundColor: colorScheme.surface,
            foregroundColor: colorScheme.onSurface,
            scrolledUnderElevation: 0,
            surfaceTintColor: Colors.transparent,
            title: Text(
              _isEditMode
                  ? 'Edit ${UserLevelEditorMode.labelFor(_editorMode)} Level'
                  : 'Create ${UserLevelEditorMode.labelFor(_editorMode)} Level',
            ),
          ),
          bottomNavigationBar: MediaQuery.removeViewInsets(
            key: const ValueKey('editor-footer'),
            context: context,
            removeBottom: true,
            child: IgnorePointer(
              ignoring: areMutationControlsLocked,
              child: SafeArea(
                        maintainBottomViewPadding: true,
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
                                _drawingHasContentNotifier,
                                _wordDrawingHasContentNotifier,
                                _wordOverlayHasContentNotifier,
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
                                    stepsEnabled: !_isGeneratingPuzzle,
                                    onStepSelected: _selectStagePreview,
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: <Widget>[
                                      Expanded(
                                        child: OutlinedButton(
                                          onPressed: areMutationControlsLocked
                                              ? null
                                              : () =>
                                                  _save(submitAfterSave: false),
                                          child: _isSaving &&
                                                  !_isSubmittingForReview
                                              ? Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: <Widget>[
                                                    SizedBox.square(
                                                      dimension: 16,
                                                      child:
                                                          CircularProgressIndicator(
                                                        strokeWidth: 2.2,
                                                        valueColor:
                                                            AlwaysStoppedAnimation<
                                                              Color
                                                            >(
                                                          colorScheme.primary,
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    const Flexible(
                                                      child: AutoSizeText(
                                                        'Saving',
                                                        maxLines: 1,
                                                        minFontSize: 10,
                                                        textAlign:
                                                            TextAlign.center,
                                                      ),
                                                    ),
                                                  ],
                                                )
                                              : const AutoSizeText(
                                                  'Save Draft',
                                                  maxLines: 1,
                                                  minFontSize: 10,
                                                  textAlign: TextAlign.center,
                                                ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: FilledButton(
                                          onPressed: areMutationControlsLocked
                                              ? null
                                              : () =>
                                                  _save(submitAfterSave: true),
                                          child: _isSubmittingForReview
                                              ? Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: <Widget>[
                                                    SizedBox.square(
                                                      dimension: 16,
                                                      child:
                                                          CircularProgressIndicator(
                                                        strokeWidth: 2.4,
                                                        backgroundColor:
                                                            colorScheme.onPrimary
                                                                .withValues(
                                                                  alpha: 0.22,
                                                                ),
                                                        valueColor:
                                                            AlwaysStoppedAnimation<
                                                              Color
                                                            >(
                                                          colorScheme.onPrimary,
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    const Flexible(
                                                      child: AutoSizeText(
                                                        'Submitting',
                                                        maxLines: 1,
                                                        minFontSize: 10,
                                                        textAlign:
                                                            TextAlign.center,
                                                      ),
                                                    ),
                                                  ],
                                                )
                                              : const AutoSizeText(
                                                  'Submit for Review',
                                                  maxLines: 1,
                                                  minFontSize: 10,
                                                  textAlign: TextAlign.center,
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
                    ),
                  ),
          body: SafeArea(
            top: false,
            child: AnimatedPadding(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.fromLTRB(16, 6, 16, bodyBottomPadding),
              child: IgnorePointer(
                ignoring: isLevelMutationLocked,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(
                      child: _editorMode == UserLevelEditorMode.highlight
                          ? _WordEditorSection(
                              scrollController: _editorScrollController,
                              isStageInteracting: _isStageInteracting,
                              controller: _wordOverlayController,
                              drawingController: _wordDrawingController,
                              hasLettersListenable:
                                  _wordOverlayHasContentNotifier,
                              hasDrawingContentListenable:
                                  _wordDrawingHasContentNotifier,
                              solutionController: _answerController,
                              solutionTextListenable: _answerTextNotifier,
                              creatorNameController: _creatorNameController,
                              promptController: _generationPromptController,
                              promptTextListenable:
                                  _generationPromptTextNotifier,
                              textTheme: textTheme,
                              colorScheme: colorScheme,
                              canvasBackgroundColor: canvasBackgroundColor,
                              isLocked: _isLocked || areMutationControlsLocked,
                              isSolutionLocked: _isSolutionEditingLocked,
                              isLoadingInitialOverlay:
                                  _isLoadingWordEditorData,
                              stagePreviewMode: _stagePreviewMode,
                              puzzleBytes: _generatedPuzzleImageBytes,
                              existingPuzzlePreviewUrlFuture:
                                  _existingPuzzlePreviewUrlFuture,
                              hasStoredPuzzleImage: _hasStoredPuzzleImage,
                              isGeneratingPuzzle: _isGeneratingPuzzle,
                              puzzleGenerationStatus:
                                  _visiblePuzzleGenerationStatus,
                              generationDifficulty: _generationDifficulty,
                              onStageInteractionChanged:
                                  _handleStageInteractionChanged,
                              normalizePoint: _normalizePoint,
                              onSelectStagePreview: _selectStagePreview,
                              onGeneratePuzzle: _generatePuzzle,
                              onCancelPuzzle: _cancelPuzzleGeneration,
                              onGenerationDifficultyChanged:
                                  _updateGenerationDifficulty,
                              onUnlockSolutionEditing:
                                  _confirmUnlockSolutionEditing,
                            )
                          : _editorMode == UserLevelEditorMode.photoSketch
                              ? _FaceEditorSection(
                                  scrollController: _editorScrollController,
                                  isStageInteracting: _isStageInteracting,
                                  sourceImageBytes: _faceSourceImageBytes,
                                  sourceImageSize: _faceSourceImageSize,
                                  sketchImageBytes: _faceSketchImageBytes,
                                  sourceTransform: _faceSourceTransform,
                                  solutionController: _answerController,
                                  solutionTextListenable: _answerTextNotifier,
                                  factController: _factController,
                                  creatorNameController: _creatorNameController,
                                  promptController: _generationPromptController,
                                  promptTextListenable: _generationPromptTextNotifier,
                                  contentCategory: _contentCategory,
                                  textTheme: textTheme,
                                  colorScheme: colorScheme,
                                  canvasBackgroundColor: canvasBackgroundColor,
                                  isLocked: _isLocked || areMutationControlsLocked,
                                  isSolutionLocked: _isSolutionEditingLocked,
                                  isLoadingSourceImage: _isLoadingFaceEditorData || _isProcessingFaceSourceImage,
                                  isGeneratingSketch: _isGeneratingFaceSketch,
                                  isGeneratingTransform: _isGeneratingAfterManipulate,
                                  stagePreviewMode: _stagePreviewMode,
                                  puzzleBytes: _generatedPuzzleImageBytes,
                                  existingPuzzlePreviewUrlFuture: _existingPuzzlePreviewUrlFuture,
                                  hasStoredPuzzleImage: _hasStoredPuzzleImage,
                                  isGeneratingPuzzle: _isGeneratingPuzzle,
                                  puzzleGenerationStatus: _visiblePuzzleGenerationStatus,
                                  generationDifficulty: _generationDifficulty,
                                  settings: _faceSketchSettings,
                                  onPickImage: _pickFaceSourceImage,
                                  onResetImageTransform: _resetFaceSourceTransform,
                                  isTransformInteractionLocked: _isFaceTransformInteractionLocked,
                                  onToggleTransformInteractionLock: _toggleFaceTransformInteractionLock,
                                  onDiscardImage: () => unawaited(_confirmDiscardFaceSourceImage()),
                                  onSourceTransformChanged: _updateFaceSourceTransform,
                                  onSourceTransformEnded: _finishFaceSourceTransform,
                                  onStageInteractionChanged: _handleStageInteractionChanged,
                                  onSelectStagePreview: _selectStagePreview,
                                  onGeneratePuzzle: _generatePuzzle,
                                  onCancelPuzzle: _cancelPuzzleGeneration,
                                  onGenerationDifficultyChanged: _updateGenerationDifficulty,
                                  onContentCategoryChanged: _updateContentCategory,
                                  onSettingsChanged: _updateFaceSketchSettings,
                                  onLiveSettingsChanged: null,
                                  onUnlockSolutionEditing: _confirmUnlockSolutionEditing,
                                )
                              : _CanvasEditorSection(
                                  scrollController: _editorScrollController,
                                  isStageInteracting: _isStageInteracting,
                                    controller: _drawingController,
                                    hasDrawingContentListenable:
                                        _drawingHasContentNotifier,
                                    solutionController: _answerController,
                                    solutionTextListenable:
                                        _answerTextNotifier,
                                    factController: _factController,
                                    creatorNameController:
                                        _creatorNameController,
                                    promptController:
                                        _generationPromptController,
                                    promptTextListenable:
                                        _generationPromptTextNotifier,
                                    textTheme: textTheme,
                                    colorScheme: colorScheme,
                                    canvasBackgroundColor:
                                        canvasBackgroundColor,
                                    isLocked: _isLocked || areMutationControlsLocked,
                                    isSolutionLocked:
                                        _isSolutionEditingLocked,
                                    stagePreviewMode: _stagePreviewMode,
                                    puzzleBytes: _generatedPuzzleImageBytes,
                                    existingPuzzlePreviewUrlFuture:
                                        _existingPuzzlePreviewUrlFuture,
                                    hasStoredPuzzleImage: _hasStoredPuzzleImage,
                                    isGeneratingPuzzle: _isGeneratingPuzzle,
                                    puzzleGenerationStatus:
                                        _visiblePuzzleGenerationStatus,
                                    generationDifficulty:
                                        _generationDifficulty,
                                    normalizePoint: _normalizePoint,
                                    onStageInteractionChanged:
                                        _handleStageInteractionChanged,
                                    onSelectStagePreview:
                                        _selectStagePreview,
                                    onGeneratePuzzle: _generatePuzzle,
                                    onCancelPuzzle: _cancelPuzzleGeneration,
                                    onGenerationDifficultyChanged:
                                        _updateGenerationDifficulty,
                                    onUnlockSolutionEditing:
                                        _confirmUnlockSolutionEditing,
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
        ),
      ),
    );
  }
}

class _FaceEditorSection extends StatelessWidget {
  final ScrollController scrollController;
  final bool isStageInteracting;
  final Uint8List? sourceImageBytes;
  final Size? sourceImageSize;
  final Uint8List? sketchImageBytes;
  final FaceSourceTransform sourceTransform;
  final TextEditingController solutionController;
  final ValueNotifier<String> solutionTextListenable;
  final TextEditingController factController;
  final TextEditingController creatorNameController;
  final TextEditingController promptController;
  final ValueNotifier<String> promptTextListenable;
  final String contentCategory;
  final TextTheme textTheme;
  final ColorScheme colorScheme;
  final Color canvasBackgroundColor;
  final bool isLocked;
  final bool isSolutionLocked;
  final bool isLoadingSourceImage;
  final bool isGeneratingSketch;
  final bool isGeneratingTransform;
  final _StagePreviewMode stagePreviewMode;
  final Uint8List? puzzleBytes;
  final Future<String>? existingPuzzlePreviewUrlFuture;
  final bool hasStoredPuzzleImage;
  final bool isGeneratingPuzzle;
  final String puzzleGenerationStatus;
  final double generationDifficulty;
  final FaceSketchSettings settings;
  final VoidCallback onPickImage;
  final VoidCallback onResetImageTransform;
  final bool isTransformInteractionLocked;
  final VoidCallback onToggleTransformInteractionLock;
  final VoidCallback onDiscardImage;
  final ValueChanged<FaceSourceTransform> onSourceTransformChanged;
  final VoidCallback onSourceTransformEnded;
  final ValueChanged<bool> onStageInteractionChanged;
  final ValueChanged<_StagePreviewMode> onSelectStagePreview;
  final VoidCallback onGeneratePuzzle;
  final VoidCallback onCancelPuzzle;
  final ValueChanged<double> onGenerationDifficultyChanged;
  final ValueChanged<String> onContentCategoryChanged;
  final ValueChanged<FaceSketchSettings> onSettingsChanged;
  final ValueChanged<FaceSketchSettings>? onLiveSettingsChanged;
  final VoidCallback onUnlockSolutionEditing;

  const _FaceEditorSection({
    required this.scrollController,
    required this.isStageInteracting,
    required this.sourceImageBytes,
    required this.sourceImageSize,
    required this.sketchImageBytes,
    required this.sourceTransform,
    required this.solutionController,
    required this.solutionTextListenable,
    required this.factController,
    required this.creatorNameController,
    required this.promptController,
    required this.promptTextListenable,
    required this.contentCategory,
    required this.textTheme,
    required this.colorScheme,
    required this.canvasBackgroundColor,
    required this.isLocked,
    required this.isSolutionLocked,
    required this.isLoadingSourceImage,
    required this.isGeneratingSketch,
    required this.isGeneratingTransform,
    required this.stagePreviewMode,
    required this.puzzleBytes,
    required this.existingPuzzlePreviewUrlFuture,
    required this.hasStoredPuzzleImage,
    required this.isGeneratingPuzzle,
    required this.puzzleGenerationStatus,
    required this.generationDifficulty,
    required this.settings,
    required this.onPickImage,
    required this.onResetImageTransform,
    required this.isTransformInteractionLocked,
    required this.onToggleTransformInteractionLock,
    required this.onDiscardImage,
    required this.onSourceTransformChanged,
    required this.onSourceTransformEnded,
    required this.onStageInteractionChanged,
    required this.onSelectStagePreview,
    required this.onGeneratePuzzle,
    required this.onCancelPuzzle,
    required this.onGenerationDifficultyChanged,
    required this.onContentCategoryChanged,
    required this.onSettingsChanged,
    this.onLiveSettingsChanged,
    required this.onUnlockSolutionEditing,
  });

  @override
  Widget build(BuildContext context) {
    final hasFaceSketch = sketchImageBytes != null;
    final solutionControlsLocked =
        isLocked || isSolutionLocked || isGeneratingPuzzle;
    final puzzleControlsLocked = isLocked || isGeneratingPuzzle;
    final header = AnimatedBuilder(
      animation: solutionTextListenable,
      builder: (context, _) {
        final isSolutionStepComplete =
            solutionTextListenable.value.trim().length >=
                    _CreateLevelScreenState._minSolutionLength &&
                hasFaceSketch;

        return Row(
          children: <Widget>[
            SizedBox(
              width: 178,
              child: Row(
                children: <Widget>[
                  _CompactActionButton(
                    icon: Icons.restart_alt_rounded,
                    label: 'Reset',
                    enabled: !solutionControlsLocked &&
                        !isGeneratingSketch &&
                        sourceImageBytes != null,
                    onPressed: onResetImageTransform,
                    disabledMessage: sourceImageBytes == null
                        ? 'Add a photo first.'
                        : isGeneratingPuzzle
                            ? 'Wait for puzzle generation to finish.'
                            : isSolutionLocked
                                ? 'Unlock the solution first to edit it.'
                                : isGeneratingSketch
                                    ? 'Wait for the sketch to finish updating.'
                                    : isLocked
                                        ? 'Submitted levels are locked and can no longer be edited.'
                                        : null,
                    dimension: 40,
                  ),
                  const SizedBox(width: 6),
                  _CompactActionButton(
                    icon: isTransformInteractionLocked
                        ? Icons.lock_rounded
                        : Icons.lock_open_rounded,
                    label: isTransformInteractionLocked
                        ? 'Frame Locked'
                        : 'Lock Frame',
                    enabled: !solutionControlsLocked &&
                        !isGeneratingSketch &&
                        sourceImageBytes != null,
                    onPressed: onToggleTransformInteractionLock,
                    disabledMessage: sourceImageBytes == null
                        ? 'Add a photo first.'
                        : isGeneratingPuzzle
                            ? 'Wait for puzzle generation to finish.'
                            : isSolutionLocked
                                ? 'Unlock the solution first to edit it.'
                                : isGeneratingSketch
                                    ? 'Wait for the sketch to finish updating.'
                                    : isLocked
                                        ? 'Submitted levels are locked and can no longer be edited.'
                                        : null,
                    dimension: 40,
                  ),
                  const SizedBox(width: 6),
                  _CompactActionButton(
                    icon: Icons.delete_outline_rounded,
                    label: 'Discard',
                    enabled: !solutionControlsLocked &&
                        !isGeneratingSketch &&
                        sourceImageBytes != null,
                    onPressed: onDiscardImage,
                    disabledMessage: sourceImageBytes == null
                        ? 'Add a photo first.'
                        : isGeneratingPuzzle
                            ? 'Wait for puzzle generation to finish.'
                            : isSolutionLocked
                                ? 'Unlock the solution first to edit it.'
                                : isGeneratingSketch
                                    ? 'Wait for the sketch to finish updating.'
                                    : isLocked
                                        ? 'Submitted levels are locked and can no longer be edited.'
                                        : null,
                    dimension: 40,
                  ),
                ],
              ),
            ),
            const Spacer(),
            _StageStepToggle(
              value: stagePreviewMode,
              canAccessPuzzleStep: isLocked || isSolutionStepComplete,
              enabled: !isGeneratingPuzzle,
              textTheme: textTheme,
              onChanged: onSelectStagePreview,
            ),
          ],
        );
      },
    );

    final stage = stagePreviewMode == _StagePreviewMode.solution
        ? _FaceSolutionStage(
            sourceImageBytes: sourceImageBytes,
            sourceImageSize: sourceImageSize,
            sketchImageBytes: sketchImageBytes,
            sourceTransform: sourceTransform,
            isLoading: isLoadingSourceImage,
            isGeneratingSketch: isGeneratingSketch,
            isGeneratingTransform: isGeneratingTransform,
            isTransformInteractionLocked: isTransformInteractionLocked,
            borderColor: colorScheme.outlineVariant,
            backgroundColor: canvasBackgroundColor,
            foregroundColor: colorScheme.onSurfaceVariant,
            isLocked: solutionControlsLocked,
            onPickImage: onPickImage,
            onTransformChanged: onSourceTransformChanged,
            onTransformEnded: onSourceTransformEnded,
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
            solutionBackdrop: sketchImageBytes == null
                ? null
                : IgnorePointer(
                    child: Opacity(
                      opacity: 0.14,
                      child: Image.memory(
                        sketchImageBytes!,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      ),
                    ),
                  ),
          );

    final metadata = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (stagePreviewMode == _StagePreviewMode.solution) ...<Widget>[
          if (isSolutionLocked) ...<Widget>[
            _SolutionPuzzleLinkNotice(
              colorScheme: colorScheme,
              onUnlock: onUnlockSolutionEditing,
            ),
            const SizedBox(height: 12),
          ],
          _ModalTextEditLauncher(
            controller: solutionController,
            label: 'Solution',
            icon: Icons.text_fields_rounded,
            enabled: !solutionControlsLocked,
            emptyLabel: 'Tap to enter the solution',
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            enableSuggestions: false,
            inputFormatters: <TextInputFormatter>[
              LengthLimitingTextInputFormatter(
                _CreateLevelScreenState._maxSolutionLength,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: _DeferredCompactSliderTile(
                  label: 'Contrast',
                  value: settings.contrast,
                  min: 1.2,
                  max: 4.0,
                  divisions: 28,
                  enabled: sourceImageBytes != null && !solutionControlsLocked,
                  valueTextBuilder: (value) => value.toStringAsFixed(1),
                  onChanged: (value) => onSettingsChanged(
                    settings.copyWith(contrast: value),
                  ),
                  onLiveChanged: (value) => onLiveSettingsChanged?.call(
                    settings.copyWith(contrast: value),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DeferredCompactSliderTile(
                  label: 'Blur',
                  value: settings.blurAmount,
                  min: 1,
                  max: 12,
                  divisions: 22,
                  enabled: sourceImageBytes != null && !solutionControlsLocked,
                  valueTextBuilder: (value) => value.toStringAsFixed(1),
                  onChanged: (value) => onSettingsChanged(
                    settings.copyWith(blurAmount: value),
                  ),
                  onLiveChanged: (value) => onLiveSettingsChanged?.call(
                    settings.copyWith(blurAmount: value),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: _DeferredCompactSliderTile(
                  label: 'Contour',
                  value: settings.edgeStrength,
                  min: 0.6,
                  max: 2.2,
                  divisions: 32,
                  enabled: sourceImageBytes != null && !solutionControlsLocked,
                  valueTextBuilder: (value) => value.toStringAsFixed(2),
                  onChanged: (value) => onSettingsChanged(
                    settings.copyWith(edgeStrength: value),
                  ),
                  onLiveChanged: (value) => onLiveSettingsChanged?.call(
                    settings.copyWith(edgeStrength: value),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DeferredCompactSliderTile(
                  label: 'Threshold',
                  value: settings.inkLevel.toDouble(),
                  min: 92,
                  max: 212,
                  divisions: 24,
                  enabled: sourceImageBytes != null && !solutionControlsLocked,
                  valueTextBuilder: (value) => value.round().toString(),
                  onChanged: (value) => onSettingsChanged(
                    settings.copyWith(inkLevel: value.round()),
                  ),
                  onLiveChanged: (value) => onLiveSettingsChanged?.call(
                    settings.copyWith(inkLevel: value.round()),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: _DeferredCompactSliderTile(
                  label: 'Detail',
                  value: settings.detailBoost,
                  min: 0.5,
                  max: 3.0,
                  divisions: 25,
                  enabled: sourceImageBytes != null && !solutionControlsLocked,
                  valueTextBuilder: (value) => value.toStringAsFixed(1),
                  onChanged: (value) => onSettingsChanged(
                    settings.copyWith(detailBoost: value),
                  ),
                  onLiveChanged: (value) => onLiveSettingsChanged?.call(
                    settings.copyWith(detailBoost: value),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DeferredCompactSliderTile(
                  label: 'Cleanup',
                  value: settings.noiseReduction,
                  min: 0,
                  max: 4,
                  divisions: 16,
                  enabled: sourceImageBytes != null && !solutionControlsLocked,
                  valueTextBuilder: (value) => value.toStringAsFixed(1),
                  onChanged: (value) => onSettingsChanged(
                    settings.copyWith(noiseReduction: value),
                  ),
                  onLiveChanged: (value) => onLiveSettingsChanged?.call(
                    settings.copyWith(noiseReduction: value),
                  ),
                ),
              ),
            ],
          ),
        ] else ...<Widget>[
          _ModalTextEditLauncher(
            controller: promptController,
            label: 'Puzzle Scene',
            icon: Icons.auto_awesome_outlined,
            enabled: !isLocked && !isGeneratingPuzzle,
            emptyLabel: 'Tap to describe the puzzle scene',
            maxLines: 3,
            editorMinLines: 8,
            editorMaxLines: 12,
            helperText: 'Describe the scene you want the generator to create.',
          ),
          const SizedBox(height: 6),
          _DeferredCompactSliderTile(
            label: 'Difficulty',
            value: generationDifficulty,
            min: 1.0,
            max: 10.0,
            divisions: 180,
            enabled: !isLocked && !isGeneratingPuzzle,
            valueTextBuilder: (val) => '${val.toStringAsFixed(2)} / 10',
            onChanged: onGenerationDifficultyChanged,
          ),
          const SizedBox(height: 10),
          AnimatedBuilder(
            animation: Listenable.merge(<Listenable>[
              solutionTextListenable,
              promptTextListenable,
            ]),
            builder: (context, _) {
              final hasPuzzlePreview =
                  puzzleBytes != null || hasStoredPuzzleImage;

              return Consumer2<AdsController?, MoneyController?>(
                builder: (context, adsController, moneyController, _) {
                  final needsAd = moneyController?.hasAllAccess() != true &&
                      adsController?.isAdAvailable() == true;

                  return SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: isGeneratingPuzzle
                          ? onCancelPuzzle
                          : () {
                              if (needsAd) {
                                adsController!.showRewardedAd(onGeneratePuzzle);
                              } else {
                                onGeneratePuzzle();
                              }
                            },
                      icon: isGeneratingPuzzle
                          ? const Icon(Icons.stop_circle_outlined)
                          : Icon(
                              needsAd
                                  ? Icons.slideshow_rounded
                                  : hasPuzzlePreview
                                      ? Icons.refresh_rounded
                                      : Icons.auto_awesome_outlined,
                            ),
                      label: Text(
                        isGeneratingPuzzle
                            ? 'Cancel Generation'
                            : needsAd
                                ? (hasPuzzlePreview
                                    ? 'Watch Ad to Regenerate'
                                    : 'Watch Ad to Generate')
                                : hasPuzzlePreview
                                    ? 'Regenerate Puzzle'
                                    : 'Generate Puzzle',
                      ),
                    ),
                  );
                },
              );
            },
          ),
          const SizedBox(height: 12),
          _ContentCategorySelector(
            label: 'Publish Category',
            value: contentCategory,
            enabled: !puzzleControlsLocked,
            textTheme: textTheme,
            colorScheme: colorScheme,
            options: UserLevelContentCategory.optionsForEditorMode(
              UserLevelEditorMode.photoSketch,
            ),
            onChanged: onContentCategoryChanged,
          ),
          const SizedBox(height: 6),
          Text(
            'Choose where this photo-based level belongs once it is reviewed.',
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          _ModalTextEditLauncher(
            controller: factController,
            label: 'Fact Hint',
            icon: Icons.lightbulb_outline,
            enabled: !puzzleControlsLocked,
            emptyLabel: 'Tap to add a fact hint',
            maxLines: 3,
          ),
          const SizedBox(height: 12),
          _ModalTextEditLauncher(
            controller: creatorNameController,
            label: 'Creator Name',
            icon: Icons.badge_outlined,
            enabled: !puzzleControlsLocked,
            emptyLabel: 'Tap to enter creator name',
            textCapitalization: TextCapitalization.words,
          ),
        ],
      ],
    );

    return _StableEditorSectionLayout(
      scrollController: scrollController,
      isStageInteracting: isStageInteracting,
      header: header,
      stage: stage,
      metadata: metadata,
      scrollStorageKey: 'face-editor-${stagePreviewMode.name}',
    );
  }
}

class _CanvasEditorSection extends StatelessWidget {
  final ScrollController scrollController;
  final bool isStageInteracting;
  final DrawingController controller;
  final ValueNotifier<bool> hasDrawingContentListenable;
  final TextEditingController solutionController;
  final ValueNotifier<String> solutionTextListenable;
  final TextEditingController factController;
  final TextEditingController creatorNameController;
  final TextEditingController promptController;
  final ValueNotifier<String> promptTextListenable;
  final TextTheme textTheme;
  final ColorScheme colorScheme;
  final Color canvasBackgroundColor;
  final bool isLocked;
  final bool isSolutionLocked;
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
  final VoidCallback onCancelPuzzle;
  final ValueChanged<double> onGenerationDifficultyChanged;
  final VoidCallback onUnlockSolutionEditing;

  const _CanvasEditorSection({
    required this.scrollController,
    required this.isStageInteracting,
    required this.controller,
    required this.hasDrawingContentListenable,
    required this.solutionController,
    required this.solutionTextListenable,
    required this.factController,
    required this.creatorNameController,
    required this.promptController,
    required this.promptTextListenable,
    required this.textTheme,
    required this.colorScheme,
    required this.canvasBackgroundColor,
    required this.isLocked,
    required this.isSolutionLocked,
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
    required this.onCancelPuzzle,
    required this.onGenerationDifficultyChanged,
    required this.onUnlockSolutionEditing,
  });

  @override
  Widget build(BuildContext context) {
    final solutionControlsLocked =
        isLocked || isSolutionLocked || isGeneratingPuzzle;
    final puzzleControlsLocked = isLocked || isGeneratingPuzzle;
    final header = AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        hasDrawingContentListenable,
        solutionTextListenable,
      ]),
      builder: (context, _) {
        final hasDrawingContent = hasDrawingContentListenable.value;
        final isSolutionStepComplete =
            solutionTextListenable.value.trim().length >=
                    _CreateLevelScreenState._minSolutionLength &&
                hasDrawingContent;
        final canEditCanvas = stagePreviewMode == _StagePreviewMode.solution &&
            !solutionControlsLocked &&
            hasDrawingContent;

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
                    disabledMessage: isLocked
                        ? 'Submitted levels are locked and can no longer be edited.'
                        : isGeneratingPuzzle
                            ? 'Wait for puzzle generation to finish.'
                            : isSolutionLocked
                                ? 'Unlock the solution first to edit it.'
                                : 'Nothing to undo yet.',
                    dimension: 40,
                  ),
                  const SizedBox(width: 6),
                  _CompactActionButton(
                    icon: Icons.delete_outline_rounded,
                    label: 'Delete',
                    enabled: canEditCanvas,
                    onPressed: controller.clear,
                    disabledMessage: isLocked
                        ? 'Submitted levels are locked and can no longer be edited.'
                        : isGeneratingPuzzle
                            ? 'Wait for puzzle generation to finish.'
                            : isSolutionLocked
                                ? 'Unlock the solution first to edit it.'
                                : 'Nothing to clear yet.',
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
              enabled: !isGeneratingPuzzle,
              textTheme: textTheme,
              onChanged: onSelectStagePreview,
            ),
          ],
        );
      },
    );

    final stage = stagePreviewMode == _StagePreviewMode.solution
        ? _DrawingStage(
            controller: controller,
            backgroundColor: canvasBackgroundColor,
            borderColor: colorScheme.outlineVariant,
            isLocked: solutionControlsLocked,
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
          );

    final metadata = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (stagePreviewMode == _StagePreviewMode.solution) ...<Widget>[
          if (isSolutionLocked) ...<Widget>[
            _SolutionPuzzleLinkNotice(
              colorScheme: colorScheme,
              onUnlock: onUnlockSolutionEditing,
            ),
            const SizedBox(height: 12),
          ],
          AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              final selectedBrush = controller.selectedBrush;
              final currentOpacity = controller.currentOpacity;
              final currentWidth = controller.currentWidth;
              final canAdjustOpacity =
                  selectedBrush != DrawingBrushType.eraser &&
                      selectedBrush != DrawingBrushType.none &&
                      selectedBrush != DrawingBrushType.text;
              final canAdjustSize = selectedBrush != DrawingBrushType.none &&
                  selectedBrush != DrawingBrushType.text;

              return Column(
                children: <Widget>[
                  SizedBox(
                    height: 48,
                    child: _BrushSelectorStrip(
                      brushes: const <DrawingBrushType>[
                        DrawingBrushType.none,
                        DrawingBrushType.pencil,
                        DrawingBrushType.marker,
                        DrawingBrushType.charcoal,
                        DrawingBrushType.eraser,
                      ],
                      selectedBrush: selectedBrush,
                      enabled: !solutionControlsLocked,
                      onSelectBrush: controller.selectBrush,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: _CompactSliderTile(
                          label: selectedBrush == DrawingBrushType.none ||
                                  selectedBrush == DrawingBrushType.text
                              ? 'Opacity'
                              : canAdjustOpacity
                                  ? 'Opacity'
                                  : 'Eraser',
                          valueText: selectedBrush == DrawingBrushType.none ||
                                  selectedBrush == DrawingBrushType.text
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
                                onChanged: canAdjustOpacity &&
                                        !solutionControlsLocked
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
                                onChanged: solutionControlsLocked ||
                                        !canAdjustSize
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
          _ModalTextEditLauncher(
            controller: solutionController,
            label: 'Solution',
            icon: Icons.text_fields_rounded,
            enabled: !solutionControlsLocked,
            emptyLabel: 'Tap to enter the solution',
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            enableSuggestions: false,
            inputFormatters: <TextInputFormatter>[
              LengthLimitingTextInputFormatter(
                _CreateLevelScreenState._maxSolutionLength,
              ),
            ],
          ),
        ] else ...<Widget>[
          _ModalTextEditLauncher(
            controller: promptController,
            label: 'Puzzle Scene',
            icon: Icons.auto_awesome_outlined,
            enabled: !isLocked && !isGeneratingPuzzle,
            emptyLabel: 'Tap to describe the puzzle scene',
            maxLines: 3,
            editorMinLines: 8,
            editorMaxLines: 12,
            helperText: 'Describe the scene you want the generator to create.',
          ),
          const SizedBox(height: 6),
          _DeferredCompactSliderTile(
            label: 'Difficulty',
            value: generationDifficulty,
            min: 1.0,
            max: 10.0,
            divisions: 180,
            enabled: !isLocked && !isGeneratingPuzzle,
            valueTextBuilder: (val) => '${val.toStringAsFixed(2)} / 10',
            onChanged: onGenerationDifficultyChanged,
          ),
          const SizedBox(height: 10),
          AnimatedBuilder(
            animation: Listenable.merge(<Listenable>[
              hasDrawingContentListenable,
              solutionTextListenable,
              promptTextListenable,
            ]),
            builder: (context, _) {
              final hasPuzzlePreview =
                  puzzleBytes != null || hasStoredPuzzleImage;

              return Consumer2<AdsController?, MoneyController?>(
                builder: (context, adsController, moneyController, _) {
                  final needsAd = moneyController?.hasAllAccess() != true &&
                      adsController?.isAdAvailable() == true;

                  return SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: isGeneratingPuzzle
                          ? onCancelPuzzle
                          : () {
                              if (needsAd) {
                                adsController!.showRewardedAd(onGeneratePuzzle);
                              } else {
                                onGeneratePuzzle();
                              }
                            },
                      icon: isGeneratingPuzzle
                          ? const Icon(Icons.stop_circle_outlined)
                          : Icon(
                              needsAd
                                  ? Icons.slideshow_rounded
                                  : hasPuzzlePreview
                                      ? Icons.refresh_rounded
                                      : Icons.auto_awesome_outlined,
                            ),
                      label: Text(
                        isGeneratingPuzzle
                            ? 'Cancel Generation'
                            : needsAd
                                ? (hasPuzzlePreview
                                    ? 'Watch Ad to Regenerate'
                                    : 'Watch Ad to Generate')
                                : hasPuzzlePreview
                                    ? 'Regenerate Puzzle'
                                    : 'Generate Puzzle',
                      ),
                    ),
                  );
                },
              );
            },
          ),
          const SizedBox(height: 12),
          _ModalTextEditLauncher(
            controller: factController,
            label: 'Fact Hint',
            icon: Icons.lightbulb_outline,
            enabled: !puzzleControlsLocked,
            emptyLabel: 'Tap to add a fact hint',
            maxLines: 3,
          ),
          const SizedBox(height: 12),
          _ModalTextEditLauncher(
            controller: creatorNameController,
            label: 'Creator Name',
            icon: Icons.badge_outlined,
            enabled: !puzzleControlsLocked,
            emptyLabel: 'Tap to enter creator name',
            textCapitalization: TextCapitalization.words,
          ),
        ],
      ],
    );

    return _StableEditorSectionLayout(
      scrollController: scrollController,
      isStageInteracting: isStageInteracting,
      header: header,
      stage: stage,
      metadata: metadata,
      scrollStorageKey: 'canvas-editor-${stagePreviewMode.name}',
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

class _FaceSolutionStage extends StatefulWidget {
  final Uint8List? sourceImageBytes;
  final Size? sourceImageSize;
  final Uint8List? sketchImageBytes;
  final FaceSourceTransform sourceTransform;
  final bool isLoading;
  final bool isGeneratingSketch;
  final bool isGeneratingTransform;
  final bool isTransformInteractionLocked;
  final Color borderColor;
  final Color backgroundColor;
  final Color foregroundColor;
  final bool isLocked;
  final VoidCallback onPickImage;
  final ValueChanged<FaceSourceTransform> onTransformChanged;
  final VoidCallback onTransformEnded;
  final ValueChanged<bool> onInteractionChanged;

  const _FaceSolutionStage({
    required this.sourceImageBytes,
    required this.sourceImageSize,
    required this.sketchImageBytes,
    required this.sourceTransform,
    required this.isLoading,
    required this.isGeneratingSketch,
    required this.isGeneratingTransform,
    required this.isTransformInteractionLocked,
    required this.borderColor,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.isLocked,
    required this.onPickImage,
    required this.onTransformChanged,
    required this.onTransformEnded,
    required this.onInteractionChanged,
  });

  @override
  State<_FaceSolutionStage> createState() => _FaceSolutionStageState();
}

class _FaceSolutionStageState extends State<_FaceSolutionStage> {
  late FaceSourceTransform _displayTransform;
  FaceSourceTransform? _gestureStartTransform;
  Offset? _gestureStartLocalImagePoint;
  Offset? _primaryPointerDownPosition;
  int _activePointers = 0;

  bool get _isInteracting =>
      _gestureStartTransform != null || _activePointers > 0;

  static const double _minFaceScale = 0.2;
  static const double _maxFaceScale = 12.0;

  FaceSourceTransform _sanitizeDisplayTransform(
    FaceSourceTransform transform,
  ) {
    return sanitizeFaceTransform(
      transform: transform,
      minScale: _minFaceScale,
      maxScale: _maxFaceScale,
    );
  }

  double _coverScale(Size stageSize, Size sourceSize) {
    return math.max(
      stageSize.width / sourceSize.width,
      stageSize.height / sourceSize.height,
    );
  }

  Offset _rotateOffset(Offset offset, double angle) {
    final cosTheta = math.cos(angle);
    final sinTheta = math.sin(angle);
    return Offset(
      (offset.dx * cosTheta) - (offset.dy * sinTheta),
      (offset.dx * sinTheta) + (offset.dy * cosTheta),
    );
  }

  Offset _stageCenterFromTransform(
    FaceSourceTransform transform,
    Size stageSize,
  ) {
    return Offset(
      (stageSize.width / 2) + (transform.offsetX * stageSize.width),
      (stageSize.height / 2) + (transform.offsetY * stageSize.height),
    );
  }

  double _effectiveScale(
    FaceSourceTransform transform,
    Size stageSize,
    Size sourceSize,
  ) {
    return _coverScale(stageSize, sourceSize) * transform.scale;
  }

  Offset _imageLocalPointForStagePoint(
    Offset stagePoint,
    FaceSourceTransform transform,
    Size stageSize,
    Size sourceSize,
  ) {
    final center = _stageCenterFromTransform(transform, stageSize);
    final effectiveScale = _effectiveScale(transform, stageSize, sourceSize);
    final delta = stagePoint - center;
    final unrotated = _rotateOffset(delta, -transform.rotation);
    return unrotated / effectiveScale;
  }

  FaceSourceTransform _transformKeepingLocalPointAtStagePoint({
    required FaceSourceTransform baseTransform,
    required Offset localImagePoint,
    required Offset stagePoint,
    required Size stageSize,
    required Size sourceSize,
  }) {
    final sanitized = _sanitizeDisplayTransform(baseTransform);
    final effectiveScale = _effectiveScale(sanitized, stageSize, sourceSize);
    final rotatedLocal = _rotateOffset(
      localImagePoint * effectiveScale,
      sanitized.rotation,
    );
    final center = stagePoint - rotatedLocal;
    return sanitized.copyWith(
      offsetX: (center.dx - (stageSize.width / 2)) / stageSize.width,
      offsetY: (center.dy - (stageSize.height / 2)) / stageSize.height,
    );
  }

  @override
  void initState() {
    super.initState();
    _displayTransform = widget.sourceTransform;
  }

  @override
  void didUpdateWidget(covariant _FaceSolutionStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sourceChanged = oldWidget.sourceImageBytes != widget.sourceImageBytes;
    if (_gestureStartTransform == null &&
        (sourceChanged ||
            oldWidget.sourceTransform != widget.sourceTransform)) {
      _displayTransform = _sanitizeDisplayTransform(widget.sourceTransform);
    }
  }

  void _handleScaleStart(ScaleStartDetails details, Size stageSize) {
    if (widget.isLocked ||
        widget.isTransformInteractionLocked ||
        widget.sourceImageBytes == null) {
      return;
    }

    final startTransform = _sanitizeDisplayTransform(_displayTransform);
    _displayTransform = startTransform;
    _gestureStartTransform = startTransform;
    final sourceSize = widget.sourceImageSize ?? const Size(1024, 1024);
    final anchorPoint = _activePointers <= 1 && _primaryPointerDownPosition != null
        ? _primaryPointerDownPosition!
        : details.localFocalPoint;
    _gestureStartLocalImagePoint = _imageLocalPointForStagePoint(
      anchorPoint,
      startTransform,
      stageSize,
      sourceSize,
    );
  }

  void _handleScaleUpdate(ScaleUpdateDetails details, Size size) {
    final startTransform = _gestureStartTransform;
    final startLocalImagePoint = _gestureStartLocalImagePoint;
    if (startTransform == null ||
        startLocalImagePoint == null ||
        widget.isLocked ||
        widget.isTransformInteractionLocked ||
        widget.sourceImageBytes == null) {
      return;
    }

    final sourceSize = widget.sourceImageSize ?? const Size(1024, 1024);
    final nextRotation = startTransform.rotation + details.rotation;
    final nextTransform = _transformKeepingLocalPointAtStagePoint(
      baseTransform: startTransform.copyWith(
        scale: startTransform.scale * details.scale,
        rotation: nextRotation,
      ),
      localImagePoint: startLocalImagePoint,
      stagePoint: details.localFocalPoint,
      stageSize: size,
      sourceSize: sourceSize,
    );

    setState(() {
      _displayTransform = _sanitizeDisplayTransform(nextTransform);
    });
  }

  void _handleScaleEnd(ScaleEndDetails details) {
    if (_gestureStartTransform == null) {
      return;
    }

    _gestureStartTransform = null;
    _gestureStartLocalImagePoint = null;
    if (_activePointers == 0) {
      widget.onInteractionChanged(false);
    }
    widget.onTransformChanged(_displayTransform);
    widget.onTransformEnded();
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (widget.isLocked ||
        widget.isTransformInteractionLocked ||
        widget.sourceImageBytes == null) {
      return;
    }

    if (_activePointers == 0) {
      _primaryPointerDownPosition = event.localPosition;
    }
    _activePointers += 1;
    widget.onInteractionChanged(true);
  }

  void _handlePointerUp(PointerEvent event) {
    if (widget.isLocked ||
        widget.isTransformInteractionLocked ||
        widget.sourceImageBytes == null) {
      return;
    }

    _activePointers = math.max(0, _activePointers - 1);
    if (_activePointers == 0) {
      _primaryPointerDownPosition = null;
    }
    if (_activePointers == 0 && _gestureStartTransform == null) {
      widget.onInteractionChanged(false);
    }
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
              final stageSize = Size(
                constraints.maxWidth,
                constraints.maxHeight,
              );
              final hasSourceImage = widget.sourceImageBytes != null;
              final canManipulateSource = hasSourceImage &&
                  !widget.isLocked &&
                  !widget.isTransformInteractionLocked;
              final showUploadTarget = !hasSourceImage &&
                  widget.sketchImageBytes == null &&
                  !widget.isLoading &&
                  !widget.isGeneratingSketch;

              final showLiveSourcePreview = hasSourceImage &&
                  (widget.sketchImageBytes == null ||
                      _isInteracting ||
                      widget.isGeneratingTransform);
              final showProcessedSketch = widget.sketchImageBytes != null &&
                  !_isInteracting &&
                  !widget.isGeneratingTransform;
              final sourceSize = widget.sourceImageSize ?? const Size(1024, 1024);
              final clampedDisplayTransform = _sanitizeDisplayTransform(
                _displayTransform,
              );
              final coverScale = math.max(
                stageSize.width / sourceSize.width,
                stageSize.height / sourceSize.height,
              );
              final effectiveScale = coverScale * clampedDisplayTransform.scale;
              final drawWidth = sourceSize.width * effectiveScale;
              final drawHeight = sourceSize.height * effectiveScale;
              final center = Offset(
                (stageSize.width / 2) +
                    (clampedDisplayTransform.offsetX * stageSize.width),
                (stageSize.height / 2) +
                    (clampedDisplayTransform.offsetY * stageSize.height),
              );

              return Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: canManipulateSource ? _handlePointerDown : null,
                onPointerUp: canManipulateSource ? _handlePointerUp : null,
                onPointerCancel: canManipulateSource ? _handlePointerUp : null,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: showUploadTarget && !widget.isLocked
                      ? widget.onPickImage
                      : null,
                  onScaleStart: !canManipulateSource
                      ? null
                      : (details) => _handleScaleStart(details, stageSize),
                  onScaleUpdate: !canManipulateSource
                      ? null
                      : (details) => _handleScaleUpdate(details, stageSize),
                  onScaleEnd: !canManipulateSource ? null : _handleScaleEnd,
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      if (hasSourceImage)
                        Positioned(
                          left: center.dx - (drawWidth / 2),
                          top: center.dy - (drawHeight / 2),
                          width: drawWidth,
                          height: drawHeight,
                          child: IgnorePointer(
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 180),
                              curve: Curves.easeOutCubic,
                              opacity: showLiveSourcePreview ? 1 : 0,
                              child: Transform.rotate(
                                angle: clampedDisplayTransform.rotation,
                                child: Image.memory(
                                  widget.sourceImageBytes!,
                                  fit: BoxFit.fill,
                                  gaplessPlayback: true,
                                  filterQuality: FilterQuality.high,
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (showProcessedSketch)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOutCubic,
                              opacity: showProcessedSketch ? 1 : 0,
                              child: Image.memory(
                                widget.sketchImageBytes!,
                                key: ValueKey(
                                  widget.sketchImageBytes.hashCode,
                                ),
                                fit: BoxFit.cover,
                                gaplessPlayback: true,
                              ),
                            ),
                          ),
                        ),
                      if (showUploadTarget)
                        _FaceUploadStagePlaceholder(
                          borderColor: widget.borderColor,
                          foregroundColor: widget.foregroundColor,
                          backgroundColor: widget.backgroundColor,
                        ),
                      if ((widget.isLoading ||
                              widget.isGeneratingTransform ||
                              widget.isGeneratingSketch) &&
                          !showUploadTarget)
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
                            ),
                            child: Center(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(28),
                                child: BackdropFilter(
                                  filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                                  child: Container(
                                    width: 180,
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.65),
                                      borderRadius: BorderRadius.circular(28),
                                      border: Border.all(
                                        color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4),
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: <Widget>[
                                        SizedBox(
                                          width: 44,
                                          height: 44,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 4,
                                            color: Theme.of(context).colorScheme.primary,
                                          ),
                                        ),
                                        const SizedBox(height: 20),
                                        Text(
                                          widget.isLoading
                                              ? 'Loading face'
                                              : 'Updating sketch',
                                          textAlign: TextAlign.center,
                                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                                fontWeight: FontWeight.w800,
                                                color: Theme.of(context).colorScheme.onSurface,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _FaceUploadStagePlaceholder extends StatelessWidget {
  final Color borderColor;
  final Color foregroundColor;
  final Color backgroundColor;

  const _FaceUploadStagePlaceholder({
    required this.borderColor,
    required this.foregroundColor,
    required this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: FractionallySizedBox(
        widthFactor: 0.5,
        heightFactor: 0.5,
        child: CustomPaint(
          painter: _DashedRRectPainter(
            color: borderColor.withValues(alpha: 0.44),
            radius: 22,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              color: backgroundColor.withValues(alpha: 0.12),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: foregroundColor.withValues(alpha: 0.07),
                      shape: BoxShape.circle,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Icon(
                        Icons.add_photo_alternate_outlined,
                        size: 28,
                        color: foregroundColor.withValues(alpha: 0.86),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Add Photo',
                    textAlign: TextAlign.center,
                    style: textTheme.titleSmall?.copyWith(
                      color: foregroundColor.withValues(alpha: 0.94),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.1,
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

class _DashedRRectPainter extends CustomPainter {
  final Color color;
  final double radius;

  const _DashedRRectPainter({
    required this.color,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(0.8),
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;

    for (final metric in path.computeMetrics()) {
      double distance = 0;
      const dashWidth = 6.0;
      const dashGap = 7.0;
      while (distance < metric.length) {
        final next = math.min(distance + dashWidth, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance += dashWidth + dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.radius != radius;
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
    final hasLocalImage = puzzleBytes != null;
    final showStoredImage = !hasLocalImage && hasStoredPuzzleImage;

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
                      return const Positioned(
                        left: -2,
                        top: -2,
                        right: -2,
                        bottom: -2,
                        child: ShimmerLoadingPlaceholder(
                          width: double.infinity,
                          height: double.infinity,
                          borderRadius: 0,
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
                      placeholder: (_, __) => Transform.scale(
                        scale: 1.05,
                        child: const ShimmerLoadingPlaceholder(
                          width: double.infinity,
                          height: double.infinity,
                          borderRadius: 0,
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
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                    ),
                    child: Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: BackdropFilter(
                          filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                          child: Container(
                            width: 180,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(28),
                              border: Border.all(
                                color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4),
                                width: 1.5,
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: <Widget>[
                                SizedBox(
                                  width: 44,
                                  height: 44,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 4,
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  statusText.isNotEmpty ? statusText.split('\n').first : 'Generating',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: Theme.of(context).colorScheme.onSurface,
                                  ),
                                ),
                                if (!statusText.contains('Safe')) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    'Do not close.',
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w600,
                                      height: 1.3,
                                    ),
                                  ),
                                ] else if (statusText.contains('\n')) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    statusText.split('\n').last,
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                                      fontWeight: FontWeight.w600,
                                      height: 1.3,
                                    ),
                                  ),
                                ]
                              ],
                            ),
                          ),
                        ),
                      ),
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

class _ContentCategorySelector extends StatelessWidget {
  final String label;
  final String value;
  final bool enabled;
  final TextTheme textTheme;
  final ColorScheme colorScheme;
  final List<String> options;
  final ValueChanged<String> onChanged;

  const _ContentCategorySelector({
    required this.label,
    required this.value,
    required this.enabled,
    required this.textTheme,
    required this.colorScheme,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: textTheme.labelMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: options
              .map(
                (option) => ButtonSegment<String>(
                  value: option,
                  label: Text(UserLevelContentCategory.labelFor(option)),
                ),
              )
              .toList(growable: false),
          selected: <String>{value},
          showSelectedIcon: false,
          onSelectionChanged: enabled
              ? (selection) => onChanged(selection.first)
              : null,
        ),
      ],
    );
  }
}

class _StageStepToggle extends StatelessWidget {
  final _StagePreviewMode value;
  final ValueChanged<_StagePreviewMode>? onChanged;
  final TextTheme textTheme;
  final bool canAccessPuzzleStep;
  final bool enabled;

  const _StageStepToggle({
    required this.value,
    required this.onChanged,
    required this.textTheme,
    required this.canAccessPuzzleStep,
    this.enabled = true,
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
        ),
      ],
      selected: <_StagePreviewMode>{value},
      showSelectedIcon: false,
      onSelectionChanged: !enabled || onChanged == null
          ? null
          : (selection) => onChanged!(selection.first),
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
  final bool stepsEnabled;
  final ValueChanged<_StagePreviewMode> onStepSelected;

  const _EditorStepProgress({
    required this.solutionProgress,
    required this.puzzleProgress,
    required this.activeStep,
    required this.colorScheme,
    required this.textTheme,
    required this.canAccessPuzzleStep,
    required this.stepsEnabled,
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
                enabled: stepsEnabled,
                colorScheme: colorScheme,
                textTheme: textTheme,
                onTap: stepsEnabled
                    ? () => onStepSelected(_StagePreviewMode.solution)
                    : null,
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
                enabled: stepsEnabled && canAccessPuzzleStep,
                colorScheme: colorScheme,
                textTheme: textTheme,
                onTap: stepsEnabled && canAccessPuzzleStep
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

class _StableEditorSectionLayout extends StatelessWidget {
  final ScrollController scrollController;
  final bool isStageInteracting;
  final Widget header;
  final Widget stage;
  final Widget metadata;
  final String scrollStorageKey;

  const _StableEditorSectionLayout({
    required this.scrollController,
    required this.isStageInteracting,
    required this.header,
    required this.stage,
    required this.metadata,
    required this.scrollStorageKey,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: SingleChildScrollView(
            key: PageStorageKey<String>(scrollStorageKey),
            controller: scrollController,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            physics: isStageInteracting
                ? const NeverScrollableScrollPhysics()
                : const ClampingScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                header,
                const SizedBox(height: 8),
                AspectRatio(
                  aspectRatio: 1,
                  child: RepaintBoundary(child: stage),
                ),
                const SizedBox(height: 12),
                metadata,
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _WordEditorSection extends StatelessWidget {
  final ScrollController scrollController;
  final bool isStageInteracting;
  final WordOverlayController controller;
  final DrawingController drawingController;
  final ValueNotifier<bool> hasLettersListenable;
  final ValueNotifier<bool> hasDrawingContentListenable;
  final TextEditingController solutionController;
  final ValueNotifier<String> solutionTextListenable;
  final TextEditingController creatorNameController;
  final TextEditingController promptController;
  final ValueNotifier<String> promptTextListenable;
  final TextTheme textTheme;
  final ColorScheme colorScheme;
  final Color canvasBackgroundColor;
  final bool isLocked;
  final bool isSolutionLocked;
  final bool isLoadingInitialOverlay;
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
  final VoidCallback onCancelPuzzle;
  final ValueChanged<double> onGenerationDifficultyChanged;
  final VoidCallback onUnlockSolutionEditing;

  const _WordEditorSection({
    required this.scrollController,
    required this.isStageInteracting,
    required this.controller,
    required this.drawingController,
    required this.hasLettersListenable,
    required this.hasDrawingContentListenable,
    required this.solutionController,
    required this.solutionTextListenable,
    required this.creatorNameController,
    required this.promptController,
    required this.promptTextListenable,
    required this.textTheme,
    required this.colorScheme,
    required this.canvasBackgroundColor,
    required this.isLocked,
    required this.isSolutionLocked,
    required this.isLoadingInitialOverlay,
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
    required this.onCancelPuzzle,
    required this.onGenerationDifficultyChanged,
    required this.onUnlockSolutionEditing,
  });

  @override
  Widget build(BuildContext context) {
    final solutionControlsLocked =
        isLocked || isSolutionLocked || isGeneratingPuzzle;
    final puzzleControlsLocked = isLocked || isGeneratingPuzzle;
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

    final header = AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        hasLettersListenable,
        hasDrawingContentListenable,
        solutionTextListenable,
      ]),
      builder: (context, _) {
        final hasLetters = hasLettersListenable.value;
        final hasDrawingContent = hasDrawingContentListenable.value;
        final isSolutionStepComplete =
            solutionTextListenable.value.trim().length >=
                    _CreateLevelScreenState._minSolutionLength &&
                hasLetters;
        final canEditDrawing = stagePreviewMode == _StagePreviewMode.solution &&
            !solutionControlsLocked &&
            hasDrawingContent;

        return Row(
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
                    disabledMessage: isLocked
                        ? 'Submitted levels are locked and can no longer be edited.'
                        : isGeneratingPuzzle
                            ? 'Wait for puzzle generation to finish.'
                            : isSolutionLocked
                                ? 'Unlock the solution first to edit it.'
                                : 'Nothing to undo yet.',
                    dimension: 40,
                  ),
                  const SizedBox(width: 6),
                  _CompactActionButton(
                    icon: Icons.delete_outline_rounded,
                    label: 'Delete',
                    enabled: canEditDrawing,
                    onPressed: drawingController.clear,
                    disabledMessage: isLocked
                        ? 'Submitted levels are locked and can no longer be edited.'
                        : isGeneratingPuzzle
                            ? 'Wait for puzzle generation to finish.'
                            : isSolutionLocked
                                ? 'Unlock the solution first to edit it.'
                                : 'Nothing to clear yet.',
                    dimension: 40,
                  ),
                ],
              ),
            ),
            const Spacer(),
            _StageStepToggle(
              value: stagePreviewMode,
              canAccessPuzzleStep: isLocked || isSolutionStepComplete,
              enabled: !isGeneratingPuzzle,
              textTheme: textTheme,
              onChanged: onSelectStagePreview,
            ),
          ],
        );
      },
    );

    final stage = Stack(
      fit: StackFit.expand,
      children: <Widget>[
        stagePreviewMode == _StagePreviewMode.solution
            ? WordOverlayStage(
                controller: controller,
                drawingController: drawingController,
                isLocked: solutionControlsLocked,
                normalizePoint: normalizePoint,
                onInteractionChanged: onStageInteractionChanged,
                borderColor: colorScheme.outlineVariant,
                backgroundColor: canvasBackgroundColor,
                foregroundColor: colorScheme.onSurfaceVariant,
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
          const Positioned(
            left: -2,
            top: -2,
            right: -2,
            bottom: -2,
            child: ShimmerLoadingPlaceholder(
              width: double.infinity,
              height: double.infinity,
              borderRadius: 0,
            ),
          ),
      ],
    );

    final metadata = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (stagePreviewMode == _StagePreviewMode.solution) ...<Widget>[
          if (isSolutionLocked) ...<Widget>[
            _SolutionPuzzleLinkNotice(
              colorScheme: colorScheme,
              onUnlock: onUnlockSolutionEditing,
            ),
            const SizedBox(height: 12),
          ],
          AnimatedBuilder(
            animation: drawingController,
            builder: (context, _) {
              final selectedBrush = drawingController.selectedBrush;
              final currentOpacity = drawingController.currentOpacity;
              final currentWidth = drawingController.currentWidth;
              final canAdjustOpacity =
                  selectedBrush != DrawingBrushType.eraser &&
                      selectedBrush != DrawingBrushType.none &&
                      selectedBrush != DrawingBrushType.text;
              final canAdjustSize = selectedBrush != DrawingBrushType.none &&
                  selectedBrush != DrawingBrushType.text;

              return Column(
                children: <Widget>[
                  SizedBox(
                    height: 48,
                    child: _BrushSelectorStrip(
                      brushes: const <DrawingBrushType>[
                        DrawingBrushType.none,
                        DrawingBrushType.text,
                        DrawingBrushType.pencil,
                        DrawingBrushType.marker,
                        DrawingBrushType.charcoal,
                        DrawingBrushType.eraser,
                      ],
                      selectedBrush: selectedBrush,
                      enabled: !solutionControlsLocked,
                      onSelectBrush: drawingController.selectBrush,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: _CompactSliderTile(
                          label: selectedBrush == DrawingBrushType.none ||
                                  selectedBrush == DrawingBrushType.text
                              ? 'Opacity'
                              : canAdjustOpacity
                                  ? 'Opacity'
                                  : 'Eraser',
                          valueText: selectedBrush == DrawingBrushType.none ||
                                  selectedBrush == DrawingBrushType.text
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
                                onChanged: canAdjustOpacity &&
                                        !solutionControlsLocked
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
                                onChanged: solutionControlsLocked ||
                                        !canAdjustSize
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
          _ModalTextEditLauncher(
            controller: solutionController,
            label: 'Solution',
            icon: Icons.text_fields_rounded,
            enabled: !solutionControlsLocked,
            emptyLabel: 'Tap to enter the word solution',
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            enableSuggestions: false,
            inputFormatters: <TextInputFormatter>[
              LengthLimitingTextInputFormatter(
                _CreateLevelScreenState._maxSolutionLength,
              ),
            ],
            helperText: 'Type the word and the letters will update when you save.',
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
          AnimatedBuilder(
            animation: controller,
            builder: (context, _) => SegmentedButton<int>(
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
              onSelectionChanged: solutionControlsLocked
                  ? null
                  : (selection) =>
                      controller.updateAllFontWeightValue(selection.first),
            ),
          ),
        ] else ...<Widget>[
          _ModalTextEditLauncher(
            controller: promptController,
            label: 'Puzzle Scene',
            icon: Icons.auto_awesome_outlined,
            enabled: !isLocked && !isGeneratingPuzzle,
            emptyLabel: 'Tap to describe the puzzle scene',
            maxLines: 3,
            editorMinLines: 8,
            editorMaxLines: 12,
            helperText: 'Describe the scene you want the generator to create.',
          ),
          const SizedBox(height: 6),
          _DeferredCompactSliderTile(
            label: 'Control Weight',
            value: generationDifficulty,
            min: 1.0,
            max: 10.0,
            divisions: 180,
            enabled: !isLocked && !isGeneratingPuzzle,
            valueTextBuilder: (val) => val.toStringAsFixed(2),
            onChanged: onGenerationDifficultyChanged,
          ),
          const SizedBox(height: 12),
          AnimatedBuilder(
            animation: Listenable.merge(<Listenable>[
              hasLettersListenable,
              solutionTextListenable,
              promptTextListenable,
            ]),
            builder: (context, _) {
              final hasPuzzlePreview =
                  puzzleBytes != null || hasStoredPuzzleImage;

              return Consumer2<AdsController?, MoneyController?>(
                builder: (context, adsController, moneyController, _) {
                  final needsAd = moneyController?.hasAllAccess() != true &&
                      adsController?.isAdAvailable() == true;

                  return SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: isGeneratingPuzzle
                          ? onCancelPuzzle
                          : () {
                              if (needsAd) {
                                adsController!.showRewardedAd(onGeneratePuzzle);
                              } else {
                                onGeneratePuzzle();
                              }
                            },
                      icon: isGeneratingPuzzle
                          ? const Icon(Icons.stop_circle_outlined)
                          : Icon(
                              needsAd
                                  ? Icons.slideshow_rounded
                                  : hasPuzzlePreview
                                      ? Icons.refresh_rounded
                                      : Icons.auto_awesome_outlined,
                            ),
                      label: Text(
                        isGeneratingPuzzle
                            ? 'Cancel Generation'
                            : needsAd
                                ? (hasPuzzlePreview
                                    ? 'Watch Ad to Regenerate'
                                    : 'Watch Ad to Generate')
                                : hasPuzzlePreview
                                    ? 'Regenerate Puzzle'
                                    : 'Generate Puzzle',
                      ),
                    ),
                  );
                },
              );
            },
          ),
          const SizedBox(height: 12),
          _ModalTextEditLauncher(
            controller: creatorNameController,
            label: 'Creator Name',
            icon: Icons.badge_outlined,
            enabled: !puzzleControlsLocked,
            emptyLabel: 'Tap to enter creator name',
            textCapitalization: TextCapitalization.words,
          ),
        ],
      ],
    );

    return _StableEditorSectionLayout(
      scrollController: scrollController,
      isStageInteracting: isStageInteracting,
      header: header,
      stage: stage,
      metadata: metadata,
      scrollStorageKey: 'word-editor-${stagePreviewMode.name}',
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
      case DrawingBrushType.text:
        return Icons.text_fields_rounded;
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
    final backgroundColor =
        selected ? colorScheme.surface : colorScheme.surfaceContainerLow;
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
  final List<DrawingBrushType> brushes;
  final DrawingBrushType selectedBrush;
  final bool enabled;
  final ValueChanged<DrawingBrushType> onSelectBrush;

  const _BrushSelectorStrip({
    required this.brushes,
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
          itemCount: widget.brushes.length,
          padding: EdgeInsets.zero,
          itemBuilder: (context, index) {
            final brush = widget.brushes[index];
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

class _SolutionPuzzleLinkNotice extends StatelessWidget {
  final ColorScheme colorScheme;
  final VoidCallback onUnlock;

  const _SolutionPuzzleLinkNotice({
    required this.colorScheme,
    required this.onUnlock,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.28),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.link_rounded,
              color: colorScheme.onPrimaryContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Solution is locked to the current puzzle. Edit the solution to clear the puzzle and generate a new one.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.tonal(
              onPressed: onUnlock,
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('Edit Solution'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModalTextEditLauncher extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool enabled;
  final String emptyLabel;
  final int maxLines;
  final int? editorMinLines;
  final int? editorMaxLines;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter> inputFormatters;
  final bool autocorrect;
  final bool enableSuggestions;
  final String? helperText;

  const _ModalTextEditLauncher({
    required this.controller,
    required this.label,
    required this.icon,
    required this.enabled,
    required this.emptyLabel,
    this.maxLines = 1,
    this.editorMinLines,
    this.editorMaxLines,
    this.textCapitalization = TextCapitalization.sentences,
    this.inputFormatters = const <TextInputFormatter>[],
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.helperText,
  });

  Future<void> _openEditor(BuildContext context) async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        fullscreenDialog: true,
        builder: (_) => _ModalTextEditPage(
          initialValue: controller.text,
          label: label,
          minLines: editorMinLines ?? (maxLines == 1 ? 1 : maxLines),
          maxLines: editorMaxLines ?? maxLines,
          textCapitalization: textCapitalization,
          inputFormatters: inputFormatters,
          autocorrect: autocorrect,
          enableSuggestions: enableSuggestions,
          helperText: helperText,
        ),
      ),
    );

    if (result == null) {
      return;
    }

    controller.value = controller.value.copyWith(
      text: result,
      selection: TextSelection.collapsed(offset: result.length),
      composing: TextRange.empty,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final colorScheme = Theme.of(context).colorScheme;
        final textTheme = Theme.of(context).textTheme;
        final value = controller.text.trim();
        final hasValue = value.isNotEmpty;

        return Opacity(
          opacity: enabled ? 1 : 0.56,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: enabled ? () => _openEditor(context) : null,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(icon, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            label,
                            style: textTheme.labelLarge?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            hasValue ? value : emptyLabel,
                            maxLines: maxLines == 1 ? 1 : 3,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodyMedium?.copyWith(
                              color: hasValue
                                  ? colorScheme.onSurface
                                  : colorScheme.onSurfaceVariant,
                              fontWeight:
                                  hasValue ? FontWeight.w600 : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Icon(
                      Icons.edit_outlined,
                      size: 18,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ModalTextEditPage extends StatefulWidget {
  final String initialValue;
  final String label;
  final int minLines;
  final int maxLines;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter> inputFormatters;
  final bool autocorrect;
  final bool enableSuggestions;
  final String? helperText;

  const _ModalTextEditPage({
    required this.initialValue,
    required this.label,
    required this.minLines,
    required this.maxLines,
    required this.textCapitalization,
    required this.inputFormatters,
    required this.autocorrect,
    required this.enableSuggestions,
    required this.helperText,
  });

  @override
  State<_ModalTextEditPage> createState() => _ModalTextEditPageState();
}

class _ModalTextEditPageState extends State<_ModalTextEditPage> {
  late final TextEditingController _draftController;
  late final FocusNode _focusNode;
  bool _isClosing = false;

  @override
  void initState() {
    super.initState();
    _draftController = TextEditingController(text: widget.initialValue);
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 60));
      if (!mounted) {
        return;
      }
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _draftController.dispose();
    super.dispose();
  }

  Future<void> _commitAndClose() async {
    if (_isClosing) {
      return;
    }
    _isClosing = true;
    FocusScope.of(context).unfocus();
    await Future<void>.delayed(const Duration(milliseconds: 90));
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(_draftController.text);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.label),
        actions: <Widget>[
          TextButton(
            onPressed: () => _commitAndClose(),
            child: const Text('Done'),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (widget.helperText != null &&
                  widget.helperText!.trim().isNotEmpty) ...<Widget>[
                Text(
                  widget.helperText!,
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              TextField(
                controller: _draftController,
                focusNode: _focusNode,
                minLines: widget.minLines,
                maxLines: widget.maxLines,
                textCapitalization: widget.textCapitalization,
                inputFormatters: widget.inputFormatters,
                autocorrect: widget.autocorrect,
                enableSuggestions: widget.enableSuggestions,
                textInputAction:
                    widget.maxLines > 1 ? TextInputAction.newline : TextInputAction.done,
                decoration: InputDecoration(
                  labelText: widget.label,
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: widget.maxLines > 1
                    ? null
                    : (_) => _commitAndClose(),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => _commitAndClose(),
                child: const Text('Save'),
              ),
            ],
          ),
        ),
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
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChangeEnd;

  const _EditorSlider({
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    required this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
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
        onChangeStart: onChangeStart,
        onChangeEnd: onChangeEnd,
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

class _DeferredCompactSliderTile extends StatefulWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final bool enabled;
  final String Function(double value) valueTextBuilder;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onLiveChanged;

  const _DeferredCompactSliderTile({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    required this.enabled,
    required this.valueTextBuilder,
    required this.onChanged,
    this.onLiveChanged,
  });

  @override
  State<_DeferredCompactSliderTile> createState() =>
      _DeferredCompactSliderTileState();
}

class _DeferredCompactSliderTileState
    extends State<_DeferredCompactSliderTile> {
  late double _draftValue;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _draftValue = widget.value;
  }

  @override
  void didUpdateWidget(covariant _DeferredCompactSliderTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isDragging && oldWidget.value != widget.value) {
      _draftValue = widget.value;
    }
  }

  @override
  Widget build(BuildContext context) {
    return _CompactSliderTile(
      label: widget.label,
      valueText: widget.valueTextBuilder(_draftValue),
      child: _EditorSlider(
        value: _draftValue.clamp(widget.min, widget.max),
        min: widget.min,
        max: widget.max,
        divisions: widget.divisions,
        onChanged: !widget.enabled
            ? null
            : (value) {
                setState(() => _draftValue = value);
                widget.onLiveChanged?.call(value);
              },
        onChangeStart:
            widget.enabled ? (_) => setState(() => _isDragging = true) : null,
        onChangeEnd: !widget.enabled
            ? null
            : (value) {
                setState(() {
                  _draftValue = value;
                  _isDragging = false;
                });
                widget.onChanged(value);
              },
      ),
    );
  }
}

class _CompactActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onPressed;
  final String? disabledMessage;
  final double dimension;

  const _CompactActionButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onPressed,
    this.disabledMessage,
    this.dimension = 48,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final backgroundColor = colorScheme.secondaryContainer.withValues(
      alpha: enabled ? 1 : 0.45,
    );
    final foregroundColor = enabled
        ? colorScheme.onSecondaryContainer
        : colorScheme.onSurfaceVariant.withValues(alpha: 0.5);
    final borderColor = enabled
        ? colorScheme.outlineVariant.withValues(alpha: 0.7)
        : colorScheme.outlineVariant.withValues(alpha: 0.36);

    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: SizedBox(
          width: dimension,
          height: dimension,
          child: Material(
            color: backgroundColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: borderColor),
            ),
            child: InkWell(
              onTap: enabled
                  ? onPressed
                  : disabledMessage == null
                      ? null
                      : () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(disabledMessage!)),
                          );
                        },
              borderRadius: BorderRadius.circular(14),
              child: Center(
                child: Icon(icon, size: 20, color: foregroundColor),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
