// Copyright 2022, the Flutter project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:logging/logging.dart';

/// Allows showing ads. A facade for `package:google_mobile_ads`.
class AdsController extends ChangeNotifier {
  static final _log = Logger('AdsController');

  final MobileAds _instance;
  final int _maxRetryCount = 25;

  int _rewardedRetryCount = 0;
  int _intersitialRetryCount = 0;
  int _consentRetryCount = 0;
  final Duration _initialDelay = const Duration(seconds: 1);

  RewardedAd? _rewardedAd;
  InterstitialAd? _interstitialAd;

  ValueNotifier<AppLifecycleState>? _lifecycleNotifier;
  TrackingStatus? _lastTrackingStatus;

  Timer? _rewardedAdTimer;
  Timer? _interstitialAdTimer;

  final rewardedAdUnitId = defaultTargetPlatform == TargetPlatform.android
      ? (kDebugMode ? 'ca-app-pub-3940256099942544/5224354917' : 'ca-app-pub-5386053272091445/7489159540')
      // iOS
      : (kDebugMode ? 'ca-app-pub-3940256099942544/1712485313' : 'ca-app-pub-5386053272091445/7457369952');

  final intersitialAdUnitId = defaultTargetPlatform == TargetPlatform.android
      ? (kDebugMode ? 'ca-app-pub-3940256099942544/1033173712' : 'ca-app-pub-5386053272091445/6030939346')
      // iOS
      : (kDebugMode ? 'ca-app-pub-3940256099942544/4411468910' : 'ca-app-pub-5386053272091445/4526285981');

  /// Creates an [AdsController] that wraps around a [MobileAds] [instance].
  AdsController(MobileAds instance) : _instance = instance;

  @override
  void dispose() {
    super.dispose();
    _rewardedAd?.dispose();
    _interstitialAd?.dispose();
    _rewardedAdTimer?.cancel();
    _interstitialAdTimer?.cancel();
    _lifecycleNotifier?.removeListener(_handleAppLifecycle);
  }

  Future<void> initialize() async {
    await _instance.initialize();
    // Preload ads after a short delay to not interfere with app startup.
    Future<void>.delayed(const Duration(seconds: 1)).then((_) {
      loadRewardedAd();
      loadInterstitialAd();
    });
  }

  bool isAdAvailable() {
    return _rewardedAd != null;
  }

  bool isInterstitialAvailable() {
    return _interstitialAd != null;
  }

  void loadRewardedAd({AdRequest? adRequest}) {
    assert(
      Platform.isAndroid || Platform.isIOS,
      'AdMob currently does not support ${Platform.operatingSystem}',
    );
    RewardedAd.load(
      adUnitId: rewardedAdUnitId,
      request: adRequest ?? const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          _rewardedRetryCount = 0; // Reset retry count on success

          // Start a 1-hour timer to reload the ad before it expires
          _rewardedAdTimer?.cancel();
          _rewardedAdTimer = Timer(const Duration(hours: 1), () {
            reloadRewardedAd();
          });

          notifyListeners();
        },
        onAdFailedToLoad: ((error) async {
          _retryWithExponentialBackoff(
            () async => loadRewardedAd(adRequest: adRequest),
            _rewardedRetryCount,
            (count) => _rewardedRetryCount = count,
            'rewarded ad load',
          );
        }),
      ),
    );
  }

  /// Loads a new interstitial ad.
  void loadInterstitialAd({AdRequest? adRequest}) {
    assert(
      Platform.isAndroid || Platform.isIOS,
      'AdMob currently does not support ${Platform.operatingSystem}',
    );
    InterstitialAd.load(
      adUnitId: intersitialAdUnitId,
      request: adRequest ?? const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _intersitialRetryCount = 0;

          // Start a 1-hour timer to reload the ad before it expires
          _interstitialAdTimer?.cancel();
          _interstitialAdTimer = Timer(const Duration(hours: 1), () {
            reloadInterstitialAd();
          });
        },
        onAdFailedToLoad: ((error) async {
          _retryWithExponentialBackoff(
            () async => loadInterstitialAd(adRequest: adRequest),
            _intersitialRetryCount,
            (count) => _intersitialRetryCount = count,
            'interstitial ad load',
          );
        }),
      ),
    );
  }

  void reloadInterstitialAd() {
    _interstitialAd?.dispose();
    _interstitialAd = null;
    loadInterstitialAd();
  }

  void reloadRewardedAd() {
    _rewardedAd?.dispose();
    _rewardedAd = null;
    loadRewardedAd();
    notifyListeners();
  }

  void showInterstitialAd() {
    if (_interstitialAd == null) {
      loadInterstitialAd();
      return;
    }
    _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        reloadInterstitialAd();
      },
      onAdFailedToShowFullScreenContent: (ad, err) {
        reloadInterstitialAd();
      },
    );

    if (Platform.isAndroid) _interstitialAd!.setImmersiveMode(true);
    _interstitialAd!.show();
    _interstitialAd = null;
  }

  /// Shows a rewarded ad if it's loaded.
  ///
  /// The [onReward] callback is executed if the user earns the reward.
  void showRewardedAd(VoidCallback onReward) {
    if (_rewardedAd == null) {
      return;
    }
    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        reloadRewardedAd();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        reloadRewardedAd();
      },
    );

    if (Platform.isAndroid) _rewardedAd!.setImmersiveMode(true);
    _rewardedAd!.show(
      onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
        onReward();
      },
    );
    _rewardedAd = null;
  }

  Future<void> requestTheLatestConsentInformation() async {
    final params = ConsentRequestParameters();
    ConsentInformation.instance.requestConsentInfoUpdate(
      params,
      () async {
        _consentRetryCount = 0;
        var status = await ConsentInformation.instance.getConsentStatus();
        if (status == ConsentStatus.obtained ||
            status == ConsentStatus.notRequired) {
          initialize();
          return;
        }
        if (await ConsentInformation.instance.isConsentFormAvailable()) {
          loadConsentForm();
        }
      },
      (FormError error) async {
        _retryWithExponentialBackoff(
          requestTheLatestConsentInformation,
          _consentRetryCount,
          (count) => _consentRetryCount = count,
          'consent info update',
        );
      },
    );
  }

  Future<void> loadConsentForm() async {
    ConsentForm.loadConsentForm(
      (ConsentForm consentForm) async {
        _consentRetryCount = 0;
        var status = await ConsentInformation.instance.getConsentStatus();
        if (status == ConsentStatus.required) {
          consentForm.show((FormError? formError) {
            loadConsentForm();
          });
        } else {
          initialize();
        }
      },
      (formError) async {
        _retryWithExponentialBackoff(
          loadConsentForm,
          _consentRetryCount,
          (count) => _consentRetryCount = count,
          'consent form load',
        );
      },
    );
  }

  /// Attaches a listener to the app's lifecycle to check for ATT changes on iOS.
  void attachLifecycleNotifier(
    ValueNotifier<AppLifecycleState> lifecycleNotifier,
  ) {
    _lifecycleNotifier?.removeListener(_handleAppLifecycle);
    lifecycleNotifier.addListener(_handleAppLifecycle);
    _lifecycleNotifier = lifecycleNotifier;
  }

  Future<void> _retryWithExponentialBackoff(
    Future<void> Function() action,
    int currentRetryCount,
    void Function(int) updateRetryCount,
    String logContext,
  ) async {
    if (currentRetryCount < _maxRetryCount) {
      final newCount = currentRetryCount + 1;
      updateRetryCount(newCount);
      final delay = _initialDelay * pow(2, newCount - 1);
      await Future.delayed(delay);
      await action();
    } else {
      _log.severe('Max retries reached for $logContext. Not retrying.');
    }
  }

  void _handleAppLifecycle() {
    if (_lifecycleNotifier?.value == AppLifecycleState.resumed) {
      if (Platform.isIOS || Platform.isMacOS) {
        _checkTrackingAuthorizationChanges();
      }
    }
  }

  Future<void> _checkTrackingAuthorizationChanges() async {
    try {
      final currentStatus =
          await AppTrackingTransparency.trackingAuthorizationStatus;
      if (_lastTrackingStatus != TrackingStatus.authorized &&
          currentStatus == TrackingStatus.authorized) {
        await requestTheLatestConsentInformation();
      }
      _lastTrackingStatus = currentStatus;
    } catch (e) {
      _log.warning('Could not check tracking authorization changes: $e');
    }
  }
}
