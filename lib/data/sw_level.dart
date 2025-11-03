import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';

/// Defines the data model for a Level.
/// This is the content data for a single level - what the player sees and interacts with.
/// Player progress (completed/unlocked status) is tracked separately.
class SWLevel {
  final String id; // Firestore document ID (e.g., 'packId__levelNr')
  final int nr; // Level number within the pack
  final String packId; // Which pack this level belongs to
  final String name; // Level display name
  final String hintType; // 'fact' or 'highlight'
  final Map<String, dynamic>
      hints; // For 'fact': {'fact': 'text'}, for 'highlight': {}
  final String puzzlePath; // URL or asset path to puzzle image
  final String puzzleThumbnailPath; // URL or asset path to thumbnail
  final String
      solutionPath; // URL or asset path to solution (SVG for highlight)
  final String tooltipStart; // Story/intro text
  final String tooltipEnd; // Story/outro text
  final bool isEnabled; // Whether this level is active
  final DateTime createdAt;
  final DateTime modifiedAt;
  final bool isBundled; // True if the level is loaded from local assets

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

  /// Factory constructor for Firestore documents
  factory SWLevel.fromFirestore(
      String id, String packId, Map<String, dynamic> data) {
    return SWLevel(
      id: id,
      nr: data['nr'] ?? 0,
      packId: packId, // Prioritize the passed packId
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
      isBundled: false, // Levels from Firestore are not bundled
    );
  }

  /// Factory constructor for bundled levels (from JSON assets)
  factory SWLevel.fromJson(String packId, Map<String, dynamic> json) {
    return SWLevel(
      id: '${packId}__${json['nr']}',
      nr: json['nr'] ?? 0,
      packId:
          packId, // Always use the packId passed to the constructor for bundled levels.
      name: json['name'] ?? 'Unnamed Level', // Deprecated 'word' field removed
      hintType: json['hintType'] ?? 'fact',
      hints: json['hints'] ?? {},
      puzzlePath:
          json['puzzlePath'] ?? '', // Deprecated 'imagePath' field removed
      puzzleThumbnailPath:
          json['puzzleThumbnailPath'] ?? '', // No old equivalent
      solutionPath:
          json['solutionPath'] ?? '', // Deprecated 'svgPath' field removed
      tooltipStart: json['tooltipStart'] ?? '',
      tooltipEnd: json['tooltipEnd'] ?? '',
      isEnabled: json['isEnabled'] ?? true,
      createdAt: DateTime.now(), // Not stored in bundled JSON
      modifiedAt: DateTime.now(),
      isBundled: true, // Levels from local JSON are bundled
    );
  }

  /// Convert to JSON (useful for caching or debugging)
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

  // Convenience getters

  /// Returns the fact hint text if this is a 'fact' type level
  String? get factHint => (hintType == 'fact' && hints.containsKey('fact'))
      ? hints['fact'] as String?
      : null;

  /// Whether this level has a fact hint available
  bool get hasFactHint => factHint != null && factHint!.isNotEmpty;

  /// Whether this level uses highlight hint type
  bool get isHighlightType => hintType == 'highlight';

  /// Whether this level has a start tooltip/story
  bool get hasStartTooltip => tooltipStart.isNotEmpty;

  /// Whether this level has an end tooltip/story
  bool get hasEndTooltip => tooltipEnd.isNotEmpty;

  String get packNameSanitized => packId
      .split('-')
      .map((word) => word[0].toUpperCase() + word.substring(1))
      .join(' ');
}
