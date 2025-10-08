// Copyright 2022, the Flutter project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// An interface of persistence stores for settings.
///
/// Implementations can range from simple in-memory storage through
/// local preferences to cloud-based solutions.
abstract class SettingsPersistence {

  Future<bool> getMusicOn();
  Future<bool> getSoundsOn();
  Future<int> getSeedColor();
  Future<String> getToken();

  Future<void> saveMusicOn(bool value);
  Future<void> saveSoundsOn(bool value);
  Future<void> saveSeedColor(int value);
  Future<void> setToken(String value);


}
