import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:operation_hermes/data/user_level_metadata.dart';

class SWLevel {
  final String id;
  final String documentId;
  final int nr;
  final String packId;
  final String name;
  final String hintType;
  final Map<String, dynamic> hints;
  final String puzzlePath;
  final String puzzleThumbnailPath;
  final String solutionPath;
  final String tooltipStart;
  final String tooltipEnd;
  final bool isEnabled;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final bool isBundled;
  final String creatorUid;
  final String creatorName;
  final String editorMode;
  final String contentCategory;
  final String submissionStatus;
  final String submissionFeedback;
  final bool isLocked;
  final String? submissionId;
  final Map<String, dynamic> editorData;

  static String inferEditorMode({
    required String? editorMode,
    required String? hintType,
  }) {
    if (editorMode != null &&
        UserLevelEditorMode.supported.contains(editorMode)) {
      return editorMode;
    }

    if (hintType == 'highlight') {
      return UserLevelEditorMode.highlight;
    }

    return UserLevelEditorMode.drawObject;
  }

  SWLevel({
    required this.id,
    required this.documentId,
    required this.nr,
    required this.packId,
    required this.name,
    required this.hintType,
    required this.hints,
    required this.puzzlePath,
    required this.puzzleThumbnailPath,
    required this.solutionPath,
    required this.tooltipStart,
    required this.tooltipEnd,
    required this.isEnabled,
    required this.createdAt,
    required this.modifiedAt,
    this.isBundled = false,
    this.creatorUid = '',
    this.creatorName = '',
    this.editorMode = UserLevelEditorMode.drawObject,
    String? contentCategory,
    this.submissionStatus = UserLevelSubmissionStatus.draft,
    this.submissionFeedback = '',
    this.isLocked = false,
    this.submissionId,
    this.editorData = const <String, dynamic>{},
  }) : contentCategory = UserLevelContentCategory.normalize(
          contentCategory,
          editorMode: editorMode,
        );

  factory SWLevel.fromFirestore(
      String id, String packId, Map<String, dynamic> data) {
    final hintType = data['hintType'] as String?;
    final resolvedNr = int.tryParse(id) ?? data['nr'] ?? 0;
    return SWLevel(
      id: '${packId}__$resolvedNr',
      documentId: id,
      nr: resolvedNr,
      packId: packId,
      name: data['name'] ?? 'Unnamed Level',
      hintType: hintType ?? 'fact',
      hints: data['hints'] ?? {},
      puzzlePath: data['puzzlePath'] ?? '',
      puzzleThumbnailPath: data['puzzleThumbnailPath'] ?? '',
      solutionPath: data['solutionPath'] ?? '',
      tooltipStart: data['tooltipStart'] ?? '',
      tooltipEnd: data['tooltipEnd'] ?? '',
      isEnabled: data['isEnabled'] ?? true,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      modifiedAt:
          (data['modifiedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isBundled: false,
      creatorUid: data['creatorUid'] ?? '',
      creatorName: data['creatorName'] ?? '',
      editorMode: inferEditorMode(
        editorMode: data['editorMode'] as String?,
        hintType: hintType,
      ),
      contentCategory: data['contentCategory'] as String?,
      submissionStatus:
          data['submissionStatus'] ?? UserLevelSubmissionStatus.draft,
      submissionFeedback: data['submissionFeedback'] ?? '',
      isLocked: data['isLocked'] ?? false,
      submissionId: data['submissionId'],
      editorData: Map<String, dynamic>.from(data['editorData'] ?? const {}),
    );
  }

  factory SWLevel.fromJson(String packId, Map<String, dynamic> json) {
    final hintType = json['hintType'] as String?;
    return SWLevel(
      id: '${packId}__${json['nr']}',
      documentId: '${packId}__${json['nr']}',
      nr: json['nr'] ?? 0,
      packId: packId,
      name: json['name'] ?? 'Unnamed Level',
      hintType: hintType ?? 'fact',
      hints: json['hints'] ?? {},
      puzzlePath: json['puzzlePath'] ?? '',
      puzzleThumbnailPath: json['puzzleThumbnailPath'] ?? '',
      solutionPath: json['solutionPath'] ?? '',
      tooltipStart: json['tooltipStart'] ?? '',
      tooltipEnd: json['tooltipEnd'] ?? '',
      isEnabled: json['isEnabled'] ?? true,
      createdAt: DateTime.now(),
      modifiedAt: DateTime.now(),
      isBundled: true,
      creatorUid: json['creatorUid'] ?? '',
      creatorName: json['creatorName'] ?? '',
      editorMode: inferEditorMode(
        editorMode: json['editorMode'] as String?,
        hintType: hintType,
      ),
      contentCategory: json['contentCategory'] as String?,
      submissionStatus:
          json['submissionStatus'] ?? UserLevelSubmissionStatus.approved,
      submissionFeedback: json['submissionFeedback'] ?? '',
      isLocked: json['isLocked'] ?? false,
      submissionId: json['submissionId'],
      editorData: Map<String, dynamic>.from(json['editorData'] ?? const {}),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'documentId': documentId,
      'nr': nr,
      'packId': packId,
      'name': name,
      'hintType': hintType,
      'hints': hints,
      'puzzlePath': puzzlePath,
      'puzzleThumbnailPath': puzzleThumbnailPath,
      'solutionPath': solutionPath,
      'tooltipStart': tooltipStart,
      'tooltipEnd': tooltipEnd,
      'isEnabled': isEnabled,
      'createdAt': createdAt.toIso8601String(),
      'modifiedAt': modifiedAt.toIso8601String(),
      'isBundled': isBundled,
      'creatorUid': creatorUid,
      'creatorName': creatorName,
      'editorMode': editorMode,
      'contentCategory': contentCategory,
      'submissionStatus': submissionStatus,
      'submissionFeedback': submissionFeedback,
      'isLocked': isLocked,
      'submissionId': submissionId,
      'editorData': editorData,
    };
  }

  String? get factHint => (hintType == 'fact' && hints.containsKey('fact'))
      ? hints['fact'] as String?
      : null;

  bool get hasFactHint => factHint != null && factHint!.isNotEmpty;
  bool get isHighlightType => hintType == 'highlight';
  bool get hasStartTooltip => tooltipStart.isNotEmpty;
  bool get hasEndTooltip => tooltipEnd.isNotEmpty;
  bool get isCreatorOwned => creatorUid.isNotEmpty;
  bool get usesDrawObjectEditor => editorMode == UserLevelEditorMode.drawObject;

  bool get hasRequiredFieldsForSubmission {
    if (creatorName.trim().isEmpty) return false;
    if (usesDrawObjectEditor && !hasFactHint) return false;
    if (solutionPath.isEmpty || puzzlePath.isEmpty) return false;
    return true;
  }
  Map<String, dynamic>? get pendingPuzzleGeneration {
    final rawPending = editorData['pendingPuzzleGeneration'];
    if (rawPending is Map) {
      return Map<String, dynamic>.from(rawPending);
    }
    return null;
  }

  bool get hasReviewReadyPuzzleImage {
    final storedFlag = editorData['hasPuzzleImage'];
    if (storedFlag is bool) {
      return storedFlag;
    }

    if (puzzlePath.isEmpty) {
      return false;
    }

    if (usesDrawObjectEditor) {
      return solutionPath.isNotEmpty && puzzlePath != solutionPath;
    }

    return true;
  }

  bool get hasPendingPuzzleGeneration {
    if (hasReviewReadyPuzzleImage) {
      return false;
    }

    final pending = pendingPuzzleGeneration;
    if (pending == null) {
      return false;
    }

    final status = '${pending['status'] ?? ''}'.trim().toLowerCase();
    final jobId = '${pending['jobId'] ?? ''}'.trim();
    return status == 'running' || jobId.isNotEmpty;
  }

  String get pendingPuzzleGenerationJobId =>
      '${pendingPuzzleGeneration?['jobId'] ?? ''}'.trim();

  String get packNameSanitized => packId
      .split('-')
      .map((word) => word[0].toUpperCase() + word.substring(1))
      .join(' ');
}
