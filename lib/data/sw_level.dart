import 'package:cloud_firestore/cloud_firestore.dart';

class SWLevel {
  final String id;
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

  SWLevel({
    required this.id,
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
  });

  factory SWLevel.fromFirestore(
      String id, String packId, Map<String, dynamic> data) {
    return SWLevel(
      id: '${packId}__${data['nr']}',
      nr: data['nr'] ?? 0,
      packId: packId,
      name: data['name'] ?? 'Unnamed Level',
      hintType: data['hintType'] ?? 'fact',
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
    );
  }

  factory SWLevel.fromJson(String packId, Map<String, dynamic> json) {
    return SWLevel(
      id: '${packId}__${json['nr']}',
      nr: json['nr'] ?? 0,
      packId: packId,
      name: json['name'] ?? 'Unnamed Level',
      hintType: json['hintType'] ?? 'fact',
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
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
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
    };
  }

  String? get factHint => (hintType == 'fact' && hints.containsKey('fact'))
      ? hints['fact'] as String?
      : null;

  bool get hasFactHint => factHint != null && factHint!.isNotEmpty;
  bool get isHighlightType => hintType == 'highlight';
  bool get hasStartTooltip => tooltipStart.isNotEmpty;
  bool get hasEndTooltip => tooltipEnd.isNotEmpty;

  String get packNameSanitized => packId
      .split('-')
      .map((word) => word[0].toUpperCase() + word.substring(1))
      .join(' ');
}
