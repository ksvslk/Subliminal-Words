// Copyright 2022, the Flutter project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:logging/logging.dart';

/// Allows showing ads. A facade for `package:google_mobile_ads`.
class AdsController extends ChangeNotifier {
  static final _log = Logger('AdsController');

  final MobileAds _instance;

  int _retryCount = 0;
  final int _maxRetryCount = 25; // Maximum number of retries
  final Duration _initialDelay = const Duration(seconds: 1); // Initial delay

  RewardedAd? _rewardedAd;

  final adUnitId = defaultTargetPlatform == TargetPlatform.android
      ? 'ca-app-pub-3940256099942544/5224354917'
      // iOS
      : 'ca-app-pub-3940256099942544/1712485313';

  /// Creates an [AdsController] that wraps around a [MobileAds] [instance].
  ///
  /// Example usage:
  ///
  ///     var controller = AdsController(MobileAds.instance);
  AdsController(MobileAds instance) : _instance = instance;

  @override
  void dispose() {
    super.dispose();
    _rewardedAd?.dispose();
  }

  /// Initializes the injected [MobileAds.instance].
  Future<void> initialize() async {
    _log.info('initialize');
    await _instance.initialize();
     Future<void>.delayed(const Duration(seconds: 1)).then((_) {
      return load(null);
    });
  }

  bool isAdAvailable() {
    return _rewardedAd != null;
  }

  void load(AdRequest? adRequestNullable) {
    assert(Platform.isAndroid || Platform.isIOS,
        'AdMob currently does not support ${Platform.operatingSystem}');
    _log.info('load');
    final adRequest = adRequestNullable ?? const AdRequest();
    RewardedAd.load(
        adUnitId: adUnitId,
        request: adRequest,
        rewardedAdLoadCallback: RewardedAdLoadCallback(onAdLoaded: (ad) {
          _rewardedAd = ad;
          _log.info('preloaded rewarded ad loaded.');
          _retryCount = 0; // Reset retry count on success
         notifyListeners();
        }, onAdFailedToLoad: ((error) async {
          _log.info('preloaded rewarded ad not loaded - $error');
          if (_retryCount < _maxRetryCount) {
            _retryCount++;
            final delay = _initialDelay * pow(2, _retryCount - 1);
            _log.info('Retrying in ${delay.inSeconds} seconds...');
            await Future.delayed(delay);
            load(adRequest);
          } else {
            _log.info('Max retries reached. Not retrying.');
          }
        })));
  }


  void reloadAd()
  {
    _rewardedAd?.dispose();
    _rewardedAd = null;
    load(null);
    notifyListeners();
  }

  Future<void> showRewardedAd(Function giveRewardCallback) async {
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
        giveRewardCallback.call();
        reloadAd();
      },
      onAdFailedToShowFullScreenContent: (RewardedAd ad, AdError error) {
        _log.info('$ad onAdFailedToShowFullScreenContent: $error');
        reloadAd();
      },
    );

    _rewardedAd!.setImmersiveMode(true);
    _rewardedAd!.show(
        onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
      _log.info(
          '$ad with reward $RewardItem(${reward.amount}, ${reward.type})');
    });
  }
}
