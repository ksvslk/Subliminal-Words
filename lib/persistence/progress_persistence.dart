import 'package:shared_preferences/shared_preferences.dart';

/// A service class for persisting player progress, such as completed levels.
///
/// It uses SharedPreferences for local storage.
class ProgressPersistence {
  static const String _completedLevelsKey = 'completed_levels';

  /// Saves a level as completed.
  ///
  /// The [levelId] should be a unique identifier, e.g., 'packId__levelNr'.
  Future<void> saveCompletedLevel(String levelId) async {
    final prefs = await SharedPreferences.getInstance();
    final completed = prefs.getStringList(_completedLevelsKey) ?? [];
    if (!completed.contains(levelId)) {
      completed.add(levelId);
      await prefs.setStringList(_completedLevelsKey, completed);
    }
  }

  /// Retrieves a set of all completed level IDs.
  Future<Set<String>> getCompletedLevels() async {
    final prefs = await SharedPreferences.getInstance();
    final completed = prefs.getStringList(_completedLevelsKey) ?? [];
    return completed.toSet();
  }

  /// Retrieves the count of completed levels for a specific pack.
  Future<int> getCompletedLevelsCountForPack(String packId) async {
    final completedLevels = await getCompletedLevels();
    return completedLevels.where((id) => id.startsWith('${packId}__')).length;
  }

  /// Retrieves the count of completed levels for a specific category.
  /// This requires a list of all packs in that category.
  Future<int> getCompletedLevelsCountForCategory(List<String> packIds) async {
    final completedLevels = await getCompletedLevels();
    return completedLevels.where((id) {
      return packIds.any((packId) => id.startsWith('${packId}__'));
    }).length;
  }
}