import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:logging/logging.dart';
import 'package:operation_hermes/settings/settings_controller.dart';

class NotificationController {
  static final Logger _log = Logger('NotificationController');

  SettingsController? _settings;
  late final String? _apnsToken;

  Future<void> initialize() async {
    if (Platform.isIOS) {
      _apnsToken = await FirebaseMessaging.instance.getAPNSToken();
    }
    askPermissions();
  }

  // First get current token and make updates if needed
  // because somehow the listening won't get you the token.
  Future<void> listenNewToken() async {
    final oldToken = await FirebaseMessaging.instance.getToken();
    checkAndStoreToken(oldToken ?? "").then((_) {
      _log.log(Level.INFO, "Start onTokenRefresh listening.");
      FirebaseMessaging.instance.onTokenRefresh.listen((fcmToken) {
        // Note: This callback is fired at each app startup and whenever a new
        // token is generated.
        _log.log(Level.INFO, "NEW! Token: $fcmToken");
        checkAndStoreToken(fcmToken);
      }).onError((err) {
        _log.log(Level.INFO, "Error getting new token: $err");
      });
    });
  }

  Future<void> askPermissions() async {
    if (Platform.isIOS && _apnsToken == null) return;
    _log.log(Level.INFO, "ask permissions!");
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );
  }

  Future<void> checkAndStoreToken(String token) async {
    _log.log(Level.INFO, "checkAndStoreToken: $token");

    if (Platform.isIOS && _apnsToken == null) return;

    // Check whether the retrieved token matches the one on your server for this user's device
    final tokenStored = await _settings?.getToken() ?? '';
    final uid = FirebaseAuth.instance.currentUser?.uid;

    _log.log(Level.INFO, "current prefs token: $tokenStored");


    if (uid != null && token != '' && (tokenStored == '' || tokenStored != token)) {
      // If you have your own server, call API to send the above token and Date() for this user's device

      // Example shown below with Firestore
      // Add token and timestamp to Firestore for this user
      final deviceToken = {
        'token': token,
        'timestamp': FieldValue.serverTimestamp(),
      };

      _log.log(Level.INFO, "Update token on cloud: $token");

      // Get user ID from Firebase Auth or your own server
      await FirebaseFirestore.instance
          .collection(Platform.isAndroid ? 'fcmTokensAndroid' : 'fcmTokensIos')
          .doc(uid)
          .set(deviceToken);

      _log.log(Level.INFO, "Save token locally: $token");
      
      // Save locally
      await _settings?.setToken(token);
    }
  }

  void attachSettings(SettingsController settingsController) {
    if (_settings == settingsController) {
      // Already attached to this instance. Nothing to do.
      return;
    }
    _settings = settingsController;
  }
}
