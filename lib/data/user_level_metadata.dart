class UserLevelEditorMode {
  static const String photoSketch = 'photo_sketch';
  static const String drawObject = 'draw_object';
  static const String highlight = 'highlight';

  static const List<String> supported = <String>[
    photoSketch,
    drawObject,
    highlight,
  ];

  static String labelFor(String mode) {
    switch (mode) {
      case photoSketch:
        return 'Photo';
      case drawObject:
        return 'Draw';
      case highlight:
        return 'Word';
      default:
        return 'Unknown';
    }
  }
}

class UserLevelContentCategory {
  static const String words = 'words';
  static const String faces = 'faces';
  static const String characters = 'characters';
  static const String objects = 'objects';

  static const List<String> supported = <String>[
    words,
    faces,
    characters,
    objects,
  ];

  static String defaultForEditorMode(String editorMode) {
    switch (editorMode) {
      case UserLevelEditorMode.highlight:
        return words;
      case UserLevelEditorMode.photoSketch:
        return faces;
      case UserLevelEditorMode.drawObject:
      default:
        return objects;
    }
  }

  static String normalize(
    String? contentCategory, {
    required String editorMode,
  }) {
    final normalized = (contentCategory ?? '').trim().toLowerCase();
    if (supported.contains(normalized)) {
      return normalized;
    }
    return defaultForEditorMode(editorMode);
  }

  static List<String> optionsForEditorMode(String editorMode) {
    switch (editorMode) {
      case UserLevelEditorMode.photoSketch:
        return const <String>[faces, characters, objects];
      case UserLevelEditorMode.highlight:
        return const <String>[words];
      case UserLevelEditorMode.drawObject:
      default:
        return const <String>[objects];
    }
  }

  static String labelFor(String contentCategory) {
    switch (contentCategory) {
      case words:
        return 'Words';
      case faces:
        return 'Faces';
      case characters:
        return 'Characters';
      case objects:
        return 'Objects';
      default:
        return 'Unknown';
    }
  }
}

class UserLevelSubmissionStatus {
  static const String draft = 'draft';
  static const String pendingReview = 'pending_review';
  static const String approved = 'approved';
  static const String rejected = 'rejected';

  static String labelFor(String status) {
    switch (status) {
      case draft:
        return 'Draft';
      case pendingReview:
        return 'Pending Review';
      case approved:
        return 'Approved';
      case rejected:
        return 'Rejected';
      default:
        return 'Unknown';
    }
  }
}
