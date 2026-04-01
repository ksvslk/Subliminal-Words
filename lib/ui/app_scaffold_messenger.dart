import 'package:flutter/material.dart';

final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

void showAppSnackBar(String message) {
  final messengerState = rootScaffoldMessengerKey.currentState;
  if (messengerState == null) {
    return;
  }

  messengerState.showSnackBar(
    SnackBar(content: Text(message)),
  );
}
