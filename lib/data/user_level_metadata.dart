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
        return 'Face';
      case drawObject:
        return 'Object';
      case highlight:
        return 'Word';
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
