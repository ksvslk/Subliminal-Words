import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A service class for persisting player progress, such as completed levels.
///
/// It uses SharedPreferences for local storage.
class ProgressPersistence {
  static const String _completedLevelsKey = 'completed_levels';
  static final _log = Logger('ProgressPersistence');

  /// Saves a level as completed.
  ///
  /// The [levelId] should be a unique identifier, e.g., 'packId__levelNr'.
  Future<void> saveCompletedLevel(String levelNr, String packId) async {
    final prefs = await SharedPreferences.getInstance();
    final completed = prefs.getStringList(_completedLevelsKey) ?? [];
    final newKey = '${packId}__$levelNr';
    if (!completed.contains(newKey)) {
      completed.add(newKey);
      await prefs.setStringList(_completedLevelsKey, completed);
    }
  }

  Future<void> saveLoadedLevels(Set<String>? additionalCompletedLevels) async {
    if (additionalCompletedLevels == null || additionalCompletedLevels.isEmpty) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final completed = prefs.getStringList(_completedLevelsKey) ?? [];
    final updatedSet = Set<String>.from(completed);
    updatedSet.addAll(additionalCompletedLevels);
    await prefs.setStringList(_completedLevelsKey, updatedSet.toList());
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

  Future<bool> isRangeOfLevelsCompleted(
      int start, int end, String packId) async {
    final completedLevels = await getCompletedLevels();
    for (int i = start; i <= end; i++) {
      final levelId = '${packId}__${i.toString()}';
      _log.info("Checking level: $levelId");
      if (!completedLevels.contains(levelId)) {
        _log.info("Level not found: $levelId");
        return false;
      }
    }
    return true;
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
