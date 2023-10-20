// Copyright 2022, the Flutter project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:logging/logging.dart';

class PreloadedRewardedAd {
  static final _log = Logger('PreloadedRewardedAd');

  final AdRequest _adRequest;
  RewardedAd? _rewardedAd;
  final String adUnitId;
  final _adCompleter = Completer<RewardedAd>();

  PreloadedRewardedAd({
    required this.adUnitId,
    AdRequest? adRequest,
  }) : _adRequest = adRequest ?? const AdRequest();

  Future<RewardedAd> get ready => _adCompleter.future;

  Future<void> load() {
    assert(Platform.isAndroid || Platform.isIOS,
        'AdMob currently does not support ${Platform.operatingSystem}');

    return RewardedAd.load(
        // This is a test ad unit ID from
        // https://developers.google.com/admob/android/test-ads. When ready,
        // you replace this with your own, production ad unit ID,
        // created in https://apps.admob.com/.
        adUnitId: adUnitId,
        request: _adRequest,
        rewardedAdLoadCallback: RewardedAdLoadCallback(onAdLoaded: (ad) {
          _rewardedAd = ad;
          _log.info('preloaded rewarded ad loaded.');
        }, onAdFailedToLoad: ((error) {
          _log.info('preloaded rewarded ad not loaded - $error');
        })));
  }

  void showRewardedAd(Function f) {
    if (_rewardedAd == null) {
      _log.info('Warning, attempt to show rewarded before loaded.');
      return;
    }
    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (RewardedAd ad) {
        _log.info('ad onAdShowedFullScreenContent.');
      },
      onAdDismissedFullScreenContent: (RewardedAd ad) {
        _log.info('$ad onAdDismissedFullScreenContent.');
        f.call();
        dispose();
        load();
      },
      onAdFailedToShowFullScreenContent: (RewardedAd ad, AdError error) {
        _log.info('$ad onAdFailedToShowFullScreenContent: $error');
        dispose();
        load();
      },
    );

    _rewardedAd!.setImmersiveMode(true);
    _rewardedAd!.show(
        onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
      _log.info(
          '$ad with reward $RewardItem(${reward.amount}, ${reward.type})');
    });
    _rewardedAd = null;
  }

  void dispose() {
    _log.info('preloaded rewarded ad being disposed');
    _rewardedAd?.dispose();
  }
}
