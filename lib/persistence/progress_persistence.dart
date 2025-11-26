import 'package:shared_preferences/shared_preferences.dart';

class ProgressPersistence {
  static const String _completedLevelsKey = 'completed_levels';

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
    if (additionalCompletedLevels == null ||
        additionalCompletedLevels.isEmpty) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final completed = prefs.getStringList(_completedLevelsKey) ?? [];
    final updatedSet = Set<String>.from(completed);
    updatedSet.addAll(additionalCompletedLevels);
    await prefs.setStringList(_completedLevelsKey, updatedSet.toList());
  }

  Future<Set<String>> getCompletedLevels() async {
    final prefs = await SharedPreferences.getInstance();
    final completed = prefs.getStringList(_completedLevelsKey) ?? [];
    return completed.toSet();
  }

  Future<int> getCompletedLevelsCountForPack(String packId) async {
    final completedLevels = await getCompletedLevels();
    return completedLevels.where((id) => id.startsWith('${packId}__')).length;
  }

  Future<bool> isRangeOfLevelsCompleted(
      int start, int end, String packId) async {
    final completedLevels = await getCompletedLevels();
    for (int i = start; i <= end; i++) {
      final levelId = '${packId}__${i.toString()}';
      if (!completedLevels.contains(levelId)) {
        return false;
      }
    }
    return true;
  }

  Future<int> getCompletedLevelsCountForCategory(List<String> packIds) async {
    final completedLevels = await getCompletedLevels();
    return completedLevels.where((id) {
      return packIds.any((packId) => id.startsWith('${packId}__'));
    }).length;
  }
}
