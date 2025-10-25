/// A class that handles saving and retrieving app settings.
abstract class SettingsPersistence {
  Future<bool> getMusicOn();
  Future<void> saveMusicOn(bool value);

  Future<bool> getSoundsOn();
  Future<void> saveSoundsOn(bool value);

  Future<int> getSeedColor();
  Future<void> saveSeedColor(int value);

  Future<String> getToken();
  Future<void> setToken(String value);

  Future<void> saveLastPackId(String packId);
  Future<String?> getLastPackId();
}