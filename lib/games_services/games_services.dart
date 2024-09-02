// Copyright 2022, the Flutter project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:games_services/games_services.dart' as gs;
import 'package:logging/logging.dart';
import 'package:operation_hermes/game/model/game_data.dart';

/// Allows awarding achievements and leaderboard scores,
/// and also showing the platforms' UI overlays for achievements
/// and leaderboards.
///
/// A facade of `package:games_services`.
class GamesServicesController {
  final achievementheSparkIgnites = "CgkI1_aOyv4PEAIQAA";
  final achievementTheRavensFall = "CgkI1_aOyv4PEAIQAQ";
  final achievementDisruptCriminalNetwork = "CgkI1_aOyv4PEAIQAg";
  final achievementVipersNestCleared = "CgkI1_aOyv4PEAIQAw";
  final achievementSerpentsEnd = "CgkI1_aOyv4PEAIQBA";
  final achievementTheLegendLivesOn = "CgkI1_aOyv4PEAIQBQ";

  final achievementCityInChaos = "CgkI1_aOyv4PEAIQCA";
  final achievementFirstStrike = "CgkI1_aOyv4PEAIQCQ";
  final achievementHighrankOfficer = "CgkI1_aOyv4PEAIQCg";
  final achievementChildsDrawing = "CgkI1_aOyv4PEAIQCw";
  final achievementVirusRelease = "CgkI1_aOyv4PEAIQDA";
  final achievementEndOfConflict = "CgkI1_aOyv4PEAIQDQ";

  final saveGameName = "savegame1337";

  static final Logger _log = Logger('GamesServicesController');
  final Completer<bool> _signedInCompleter = Completer();
  Future<bool> get signedIn => _signedInCompleter.future;

  /// Unlocks an achievement on Game Center / Play Games.
  ///
  /// You must provide the achievement ids via the [iOS] and [android]
  /// parameters.
  ///
  /// Does nothing when the game isn't signed into the underlying
  /// games service.
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

  /// Signs into the underlying games service.
  Future<void> initialize() async {
    try {
      await gs.GamesServices.signIn();
      // The API is unclear so we're checking to be sure. The above call
      // returns a String, not a boolean, and there's no documentation
      // as to whether every non-error result means we're safely signed in.
      final signedIn = await gs.GamesServices.isSignedIn;
      _signedInCompleter.complete(signedIn);

      //final savedGame = await gs.GamesServices.loadGame(name: "a");
      //final saveGameJson = savedGame.jsify();
    } catch (e) {
      _log.severe('Cannot log into GamesServices: $e');
      _signedInCompleter.complete(false);
    }
  }

  /// Launches the platform's UI overlay with achievements.
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

  Future<void> unlockAchievementForLevel(int nr) async {
    switch (nr) {
      case 11:
        awardAchievement(
            iOS: achievementheSparkIgnites, android: achievementheSparkIgnites);
      case 25:
        awardAchievement(
            iOS: achievementTheRavensFall, android: achievementTheRavensFall);
      case 40:
        awardAchievement(
            iOS: achievementDisruptCriminalNetwork,
            android: achievementDisruptCriminalNetwork);
      case 55:
        awardAchievement(
            iOS: achievementVipersNestCleared,
            android: achievementVipersNestCleared);
      case 85:
        awardAchievement(
            iOS: achievementSerpentsEnd, android: achievementSerpentsEnd);
      case 100:
        awardAchievement(
            iOS: achievementTheLegendLivesOn,
            android: achievementTheLegendLivesOn);
      case 112: // City In Chaos x 50 - Chaos is unraveling the fabric of the city.
        awardAchievement(
            iOS: achievementCityInChaos, android: achievementCityInChaos);
      case 125:
        awardAchievement(
            iOS: achievementFirstStrike, android: achievementFirstStrike);
      case 154:
        awardAchievement(
            iOS: achievementHighrankOfficer,
            android: achievementHighrankOfficer);
      case 168:
        awardAchievement(
            iOS: achievementChildsDrawing, android: achievementChildsDrawing);
      case 184:
        awardAchievement(
            iOS: achievementVirusRelease, android: achievementVirusRelease);
      case 200:
        awardAchievement(
            iOS: achievementEndOfConflict, android: achievementEndOfConflict);
    }
  }

  Future<void> saveGame(int progress) async {
    if (await signedIn) {
      try {
        final gameData = await loadGame();
        _log.log(Level.INFO,
            "Cloud progress: ${gameData?.progress}, local progress: $progress");
        if (gameData?.progress.compareTo(progress) == 1) return;
        final data = jsonEncode(GameData(progress).toJson());
        final result =
            await gs.SaveGame.saveGame(data: data, name: saveGameName);
        _log.log(Level.INFO, "Save game result: $result");
      } catch (e) {
        _log.severe('Could not save game: $e');
      }
    }
  }

  Future<GameData?> loadGame() async {
    if (await signedIn) {
      final savedGamesList = await gs.SaveGame.getSavedGames();
      if (savedGamesList != null && savedGamesList.isNotEmpty) {
        try {
          _log.log(Level.INFO,
              'Is user logged in:${await gs.GameAuth.isSignedIn}, ${await gs.GamesServices.isSignedIn}');
          final result = await gs.SaveGame.loadGame(name: saveGameName);
          if (result != null) {
            final Map json = jsonDecode(result);
            final gameData = GameData.fromJson(json);
            _log.log(Level.INFO, "Player progress: ${gameData.progress}");
            return gameData;
          }
          _log.log(Level.INFO, "Could not load game.");
          return null;
        } catch (e) {
          _log.severe('Could not load game: $e');
          return null;
        }
      }
    }
    return null;
  }
}
