// Copyright 2022, the Flutter project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.


import 'package:operation_hermes/C.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'settings_persistence.dart';


/// An implementation of [SettingsPersistence] that uses
/// `package:shared_preferences`.
class LocalStorageSettingsPersistence extends SettingsPersistence {
  final Future<SharedPreferences> instanceFuture =
      SharedPreferences.getInstance();
      

  // GET
  @override
  Future<bool> getMusicOn() async {
    final prefs = await instanceFuture;
    return prefs.getBool('musicOn') ?? true;
  }


  @override
  Future<bool> getSoundsOn() async {
    final prefs = await instanceFuture;
    return prefs.getBool('soundsOn') ?? true;
  }

    @override
  Future<int> getSeedColor() async {
    final prefs = await instanceFuture;
    return prefs.getInt('seedColor') ?? C.DEFAULT_THEME_COLOR.value;
  }

  // SET
  @override
  Future<void> saveMusicOn(bool value) async {
    final prefs = await instanceFuture;
    await prefs.setBool('musicOn', value);
  }

  @override
  Future<void> saveSoundsOn(bool value) async {
    final prefs = await instanceFuture;
    await prefs.setBool('soundsOn', value);
  }

  @override
  Future<void> saveSeedColor(int value) async {
    final prefs = await instanceFuture;
    await prefs.setInt('seedColor', value);
  }

}
