class ProgressAchievement {
    final String name;
    final String packId;
    final int levelsToUnlock;
    final String achievementIdAppstore;
    final String achievementIdGoogleplay;

  ProgressAchievement({
    required this.name,
    required this.packId,
    required this.levelsToUnlock,
    required this.achievementIdAppstore,
    required this.achievementIdGoogleplay
  });

  factory ProgressAchievement.fromMap(Map<String, dynamic> data) {
    return ProgressAchievement(
      packId: data['packId'] ?? '',
      name: data['name'] ?? '',
      levelsToUnlock: data['levelsToUnlock'] ?? 0,
      achievementIdAppstore: data['achievementIdAppstore'] ?? '',
      achievementIdGoogleplay: data['achievementIdGoogleplay'] ?? '',
    );
  }
}