import 'package:flutter/material.dart';
import 'package:operation_hermes/game/play_session.dart';

void main() => runApp(const MyApp());

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Subliminal Words',
      theme: ThemeData(
          useMaterial3: true,
          // Define the default brightness and colors.
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color.fromARGB(255, 0, 179, 255),
            brightness: Brightness.light,
          ),
          fontFamily: 'Gabarito'),
      darkTheme: ThemeData(
          useMaterial3: true,
          // Define the default brightness and colors.
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color.fromARGB(255, 0, 179, 255),
            brightness: Brightness.dark,
          ),
          fontFamily: 'Gabarito'),
      home: const PlaySession(),
    );
  }
}
