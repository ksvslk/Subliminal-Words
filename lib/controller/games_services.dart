// Copyright 2022, the Flutter project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:games_services/games_services.dart' as gs;
import 'package:games_services/games_services.dart';
import 'package:logging/logging.dart';

class GamesServicesController {

  final saveGameName = "new_save_game";

  static final Logger _log = Logger('GamesServicesController');
  final Completer<bool> _signedInCompleter = Completer();
  Future<bool> get signedIn => _signedInCompleter.future;

  Future<void> awardAchievement(
      {required String iOS, required String android}) async {
    if (!await signedIn) {
      _log.warning('Trying to award achievement when not logged in.');
      return;
    }

    try {
      await gs.GamesServices.unlock(
        achievement: gs.Achievement(
          androidID: android,
          iOSID: iOS,
        ),
      );
    } catch (e) {
      _log.severe('Cannot award achievement: $e');
    }
  }

  Future<String?> getPlayerID() async {
    return await gs.GamesServices.getPlayerID();
  }

  Future<void> signInWithCredential() async {
    try {
      final UserCredential? credential = await _getPlatformCredential();
      if (credential?.user?.uid == null) {
        await _signInAnonymously();
      }
    } catch (e) {
      await _signInAnonymously();
    }
  }

  Future<UserCredential?> _getPlatformCredential() async {
    try {
      if (Platform.isAndroid) {
          final authCode = await GameAuth.getAuthCode(
              "549374376791-sh7249jmselsk4duti6jbi9g8b1dgfj4.apps.googleusercontent.com");
          if (authCode == null) return null;

          return FirebaseAuth.instance.signInWithCredential(
            PlayGamesAuthProvider.credential(serverAuthCode: authCode),
          );
        }

        if (Platform.isIOS) {
          return FirebaseAuth.instance.signInWithCredential(
            GameCenterAuthProvider.credential(),
          );
        }
    } catch(err) {
        return null;
    }
  
  }

  Future<void> _signInAnonymously() async {
    try {
      await FirebaseAuth.instance.signInAnonymously();
    } catch (e) {
      _log.warning('Anonymous authentication failed: $e');
    }
  }

  Future<void> initialize() async {
    try {
      await gs.GamesServices.signIn().then((onValue) {
        signInWithCredential();
      }).onError((err, st){
        _signInAnonymously();
      });
      final signedIn = await gs.GamesServices.isSignedIn;
      if (!_signedInCompleter.isCompleted) {
        _signedInCompleter.complete(signedIn);
      }
    } catch (e) {
      _log.severe('Cannot log into GamesServices: $e');
      if (!_signedInCompleter.isCompleted) {
        _signedInCompleter.complete(false);
      }
    }
  }

  Future<void> showAchievements() async {
    if (!await signedIn) {
      _log.severe('Trying to show achievements when not logged in.');
      return;
    }
    try {
      await gs.GamesServices.showAchievements();
    } catch (e) {
      _log.severe('Cannot show achievements: $e');
    }
  }

  Future<void> saveGame(Set<String> completedLevels) async {
    if (await signedIn) {
      try {
        final data = jsonEncode(completedLevels.toList());
        await gs.SaveGame.saveGame(data: data, name: saveGameName);
      } catch (e) {
        _log.severe('Could not save game: $e');
      }
    }
  }

  Future<Set<String>?> loadGame() async {
    if (await signedIn) {
      final savedGamesList = await gs.SaveGame.getSavedGames();
      if (savedGamesList != null && savedGamesList.isNotEmpty) {
        try {
          final result = await gs.SaveGame.loadGame(name: saveGameName);
          if (result != null) {
            final List<dynamic> completedLevels = jsonDecode(result);
            final loadedCompletedLevels = completedLevels.map((a) => a.toString()).toSet();
            return loadedCompletedLevels;
          }
          _log.warning("Could not load game.");
          return null;
        } catch (e) {
          _log.warning('Could not load game: $e');
          return null;
        }
      }
    }
    return null;
  }
}
