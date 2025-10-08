import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:logging/logging.dart';
import 'package:operation_hermes/controller/settings_controller.dart';

class NotificationController {
  static final Logger _log = Logger('NotificationController');

  SettingsController? _settings;

  Future<void> initialize() async {
    await askPermissions();
    if (Platform.isMacOS || Platform.isIOS) {
      await FirebaseMessaging.instance.getAPNSToken();
    }
    final oldToken =  await FirebaseMessaging.instance.getToken();
    await checkAndStoreToken(oldToken ?? "");
    FirebaseMessaging.instance.onTokenRefresh.listen((fcmToken) {
      // Note: This callback is fired at each app startup and whenever a new
      // token is generated.
      checkAndStoreToken(fcmToken);
    }).onError((err) {
      _log.log(Level.WARNING, "Error getting new token: $err");
    });
  }


  Future<void> askPermissions() async {
    //if (Platform.isIOS && _apnsToken == null) return;
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
    // Check whether the retrieved token matches the one on your server for this user's device
    final tokenStored = await _settings?.getToken() ?? '';
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid != null &&
        token != '' &&
        (tokenStored == '' || tokenStored != token)) {
      // If you have your own server, call API to send the above token and Date() for this user's device

      // Example shown below with Firestore
      // Add token and timestamp to Firestore for this user
      final deviceToken = {
        'token': token,
        'timestamp': FieldValue.serverTimestamp(),
      };

      // Get user ID from Firebase Auth or your own server
      await FirebaseFirestore.instance
          .collection(Platform.isAndroid ? 'fcmTokensAndroid' : 'fcmTokensIos')
          .doc(uid)
          .set(deviceToken);

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
