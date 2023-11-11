import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:logging/logging.dart';
import 'package:operation_hermes/ads/ads_controller.dart';
import 'package:operation_hermes/game/game_field.dart';
import 'package:operation_hermes/game/game_field_wrapper.dart';
import 'package:operation_hermes/game/model/level_model.dart';
import 'package:operation_hermes/games_services/games_services.dart';
import 'package:operation_hermes/in_app_purchase/in_app_purchase_controller.dart';
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
  //debugPaintSizeEnabled = true;
  // Subscribe to log messages.
  Logger.root.onRecord.listen((record) {
    if (record.level >= Level.INFO) {
      dev.log(
        record.message,
        time: record.time,
        level: record.level.value,
        name: record.loggerName,
        zone: record.zone,
        error: record.error,
        stackTrace: record.stackTrace,
      );
    }
  });

  WidgetsFlutterBinding.ensureInitialized();

  _log.info('Going full screen');
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.edgeToEdge,
  );

  AdsController? adsController;
  if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
    /// Prepare the google_mobile_ads plugin so that the first ad loads
    /// faster. This can be done later or with a delay if startup
    /// experience suffers.
    adsController = AdsController(MobileAds.instance);
    adsController.initialize();
  }

  GamesServicesController? gamesServicesController;
  if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
     gamesServicesController = GamesServicesController()
       // Attempt to log the player in.
       ..initialize();
  }

  InAppPurchaseController? inAppPurchaseController;
  if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
    inAppPurchaseController = InAppPurchaseController(InAppPurchase.instance)
      // Subscribing to [InAppPurchase.instance.purchaseStream] as soon
      // as possible in order not to miss any updates.
      ..subscribe();
  }

  runApp(
    MyApp(
        settingsPersistence: LocalStorageSettingsPersistence(),
        levelPersistence: LocalStorageLevelPersistence(),
        adsController: adsController,
        inAppPurchaseController: inAppPurchaseController,
        gamesServicesController: gamesServicesController),
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

class MyApp extends StatelessWidget {
  final SettingsPersistence settingsPersistence;
  final LevelPersistence levelPersistence;
  final AdsController? adsController;
  final InAppPurchaseController? inAppPurchaseController;
  final GamesServicesController? gamesServicesController;

  const MyApp(
      {super.key,
      required this.settingsPersistence,
      required this.levelPersistence,
      required this.adsController,
      required this.inAppPurchaseController,
      required this.gamesServicesController});

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
        Provider<GamesServicesController?>.value(
              value: gamesServicesController),
        ChangeNotifierProvider<AdsController?>.value(value: adsController),
        ChangeNotifierProvider<InAppPurchaseController?>.value(
            value: inAppPurchaseController),
        ChangeNotifierProxyProvider<ValueNotifier<AppLifecycleState>,
            LevelModel>(
          lazy: false,
          create: (context) => LevelModel(
            persistence: levelPersistence,
          )..initialize(),
          update: (BuildContext context,
              ValueNotifier<AppLifecycleState> lifecycleNotifier,
              LevelModel? levelModel) {
            if (levelModel == null) throw ArgumentError.notNull();
            levelModel.attachLifecycleNotifier(lifecycleNotifier);
            return levelModel;
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
      builder: (context, child) {
        final settingsController = context.read<SettingsController>();
        return ValueListenableBuilder(
          valueListenable: settingsController.seedColor,
          builder: (context, changingSeedColor, child) {
            return MaterialApp(
                title: 'Subliminal Words',
                theme: ThemeData(
                    scaffoldBackgroundColor: Colors.white,
                    useMaterial3: true,
                    // Define the default brightness and colors.
                    colorScheme: ColorScheme.fromSeed(
                      seedColor: Color(changingSeedColor),
                      brightness: Brightness.light,
                    ),
                    fontFamily: 'Gabarito'),
                darkTheme: ThemeData(
                    scaffoldBackgroundColor: Colors.black,
                    useMaterial3: true,
                    // Define the default brightness and colors.
                    colorScheme: ColorScheme.fromSeed(
                      seedColor: Color(changingSeedColor),
                      brightness: Brightness.dark,
                    ),
                    fontFamily: 'Gabarito'),
                home: const Scaffold(
                  body: GameFieldWrapper(),
                ));
          },
        );
      },
    ));
  }
}
