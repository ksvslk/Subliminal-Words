import 'package:flutter/material.dart';
import 'package:operation_hermes/game/play_session.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaySession();
  }
}
