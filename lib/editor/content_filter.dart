class ContentFilter {
  static final List<String> _blockedTerms = <String>[
    'fuck',
    'shit',
    'bitch',
    'asshole',
    'cunt',
    'nigger',
    'fag',
    'porn',
    'sex',
  ];

  static bool containsBlockedTerm(String input) {
    final normalized = input.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }

    return _blockedTerms.any(normalized.contains);
  }
}
