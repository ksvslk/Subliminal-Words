import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:operation_hermes/game/game_field_wrapper.dart';
import 'package:operation_hermes/level/level_controller.dart';
import 'package:operation_hermes/level/persistence/level_persistence.dart';
import 'package:operation_hermes/level/persistence/local_storage_level_persistence.dart';
import 'dart:developer' as dev;
import 'settings/persistence/settings_persistence.dart';
import 'settings/persistence/local_storage_settings_persistence.dart';
import 'app_lifecycle/app_lifecycle.dart';
import 'package:provider/provider.dart';
import 'settings/settings_controller.dart';
import 'audio/audio_controller.dart';

Future<void> main() async {
  // Subscribe to log messages.
  Logger.root.onRecord.listen((record) {
    dev.log(
      record.message,
      time: record.time,
      level: record.level.value,
      name: record.loggerName,
      zone: record.zone,
      error: record.error,
      stackTrace: record.stackTrace,
    );
  });

  WidgetsFlutterBinding.ensureInitialized();

  _log.info('Going full screen');
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.edgeToEdge,
  );

  runApp(
    MyApp(
        settingsPersistence: LocalStorageSettingsPersistence(),
        levelPersistence: LocalStorageLevelPersistence()),
  );
}

Logger _log = Logger('main.dart');
//Color.fromARGB(255, 40, 0, 161)
//Color.fromARGB(255, 255, 0, 187)
//Color.fromARGB(255, 0, 255, 0)
//Color.fromARGB(255, 0, 255, 255)
//Color.fromARGB(255, 0, 0, 255)
//Color.fromARGB(255, 255, 255, 0)
//Color.fromARGB(255, 255, 0, 0)

const mainSeedColor = Color.fromARGB(255, 0, 0, 255);

class MyApp extends StatelessWidget {
  final SettingsPersistence settingsPersistence;
  final LevelPersistence levelPersistence;

  const MyApp({super.key, required this.settingsPersistence, required this.levelPersistence});

  @override
  Widget build(BuildContext context) {
    return AppLifecycleObserver(
      child: MultiProvider(
        providers: [
          Provider<SettingsController>(
            lazy: false,
            create: (context) => SettingsController(
              persistence: settingsPersistence,
            )..loadStateFromPersistence(),
          ),
          ProxyProvider<ValueNotifier<AppLifecycleState>, LevelController>(
            lazy: false, // Ensure that LevelController is created on startup
            create: (context) => LevelController(
              persistence: levelPersistence,
            )..initialize(),
            dispose: (context, levelController) {
              levelController.dispose();
            },
            update: (BuildContext context,
                ValueNotifier<AppLifecycleState> lifecycleNotifier,
                LevelController? levelController) {
              if (levelController == null) throw ArgumentError.notNull();
              levelController.attachLifecycleNotifier(lifecycleNotifier);
              return levelController;
            },
          ),
          ProxyProvider2<SettingsController, ValueNotifier<AppLifecycleState>,
              AudioController>(
            // Ensures that the AudioController is created on startup,
            // and not "only when it's needed", as is default behavior.
            // This way, music starts immediately.
            lazy: false,
            create: (context) => AudioController()..initialize(),
            update: (context, settings, lifecycleNotifier, audio) {
              if (audio == null) throw ArgumentError.notNull();
              audio.attachSettings(settings);
              audio.attachLifecycleNotifier(lifecycleNotifier);
              return audio;
            },
            dispose: (context, audio) => audio.dispose(),
          ),
        ],
        child: MaterialApp(
          title: 'Subliminal Words',
          theme: ThemeData(
              useMaterial3: true,
              // Define the default brightness and colors.
              colorScheme: ColorScheme.fromSeed(
                seedColor: mainSeedColor,
                brightness: Brightness.light,
              ),
              fontFamily: 'Gabarito'),
          darkTheme: ThemeData(
              useMaterial3: true,
              // Define the default brightness and colors.
              colorScheme: ColorScheme.fromSeed(
                seedColor: mainSeedColor,
                brightness: Brightness.dark,
              ),
              fontFamily: 'Gabarito'),
          home: const GameFieldWrapper(),
        ),
      ),
    );
  }
}
