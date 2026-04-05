import 'package:flutter/material.dart';

final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

final GlobalKey<NavigatorState> rootNavigatorKey =
    GlobalKey<NavigatorState>();

void showAppSnackBar(String message) {
  final messengerState = rootScaffoldMessengerKey.currentState;
  if (messengerState == null) {
    return;
  }

  messengerState.showSnackBar(
    SnackBar(content: Text(message)),
  );
}
