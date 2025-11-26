// Copyright 2022, the Flutter project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:flutter/widgets.dart';
import 'package:operation_hermes/config/C.dart';

import '../persistence/settings_persistence.dart';

class SettingsController {
  final SettingsPersistence _persistence;

  SettingsPersistence get persistence => _persistence;
  ValueNotifier<bool> soundsOn = ValueNotifier(false);
  ValueNotifier<bool> musicOn = ValueNotifier(false);
  ValueNotifier<int> seedColor = ValueNotifier(C.defaultThemeColor.toARGB32());

  SettingsController({required SettingsPersistence persistence})
      : _persistence = persistence;

  Future<void> loadStateFromPersistence() async {
    await Future.wait([
      _persistence.getSoundsOn().then((value) => soundsOn.value = value),
      _persistence.getMusicOn().then((value) => musicOn.value = value),
      _persistence.getSeedColor().then((value) => seedColor.value = value),
    ]);
  }

  void changeSeedColor(Color color) {
    seedColor.value = color.toARGB32();
    _persistence.saveSeedColor(seedColor.value);
  }

  Future<void> setToken(String token) async {
    await _persistence.setToken(token);
  }

  Future<String> getToken() async {
    return await _persistence.getToken();
  }

  void toggleMusicOn() {
    musicOn.value = !musicOn.value;
    _persistence.saveMusicOn(musicOn.value);
  }

  void toggleSoundsOn() {
    soundsOn.value = !soundsOn.value;
    _persistence.saveSoundsOn(soundsOn.value);
  }
}
