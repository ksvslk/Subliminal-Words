import 'dart:io';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:logging/logging.dart';
import 'package:operation_hermes/config/C.dart';
import 'package:operation_hermes/controller/ads_controller.dart';
import 'package:operation_hermes/controller/money_controller.dart';
import 'package:operation_hermes/ui/screen/game_field_screen.dart';
import 'package:operation_hermes/change_notifier/level_model.dart';
import 'package:operation_hermes/controller/games_services.dart';
import 'package:operation_hermes/controller/firebase_service.dart';
import 'package:operation_hermes/persistence/level_persistence.dart';
import 'package:operation_hermes/persistence/progress_persistence.dart';
import 'package:operation_hermes/persistence/local_storage_level_persistence.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'dart:developer' as dev;
import 'persistence/settings_persistence.dart';
import 'persistence/local_storage_settings_persistence.dart';
import 'app_lifecycle.dart';
import 'package:provider/provider.dart';
import 'controller/settings_controller.dart';
import 'controller/audio_controller.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:operation_hermes/data/category.dart';


@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

Future<void> initPurchases() async {
  await Purchases.setLogLevel(LogLevel.debug);
  PurchasesConfiguration configuration;
  if (Platform.isAndroid) {
    configuration = PurchasesConfiguration("goog_WYNwAFMjoBMCxqKqdGpqsWmqcft");
  } else {
    configuration = PurchasesConfiguration("appl_OzsUYLHSwWLHXbRWclOKXSiGzYY");
  }
  await Purchases.configure(configuration);
}

Future<void> setUpRemoteConfig() async {
  final remoteConfig = FirebaseRemoteConfig.instance;
  await remoteConfig.setConfigSettings(
    RemoteConfigSettings(
        fetchTimeout: const Duration(minutes: 1),
        minimumFetchInterval:
            const Duration(hours: 3) 
        ),
  );
  await remoteConfig.setDefaults(const {
    C.progressAchievemetns: "",
    C.adsDisplayLevelLimit: 9
  });
  remoteConfig.onConfigUpdated.listen((event) async {
    await remoteConfig.activate();
  });
  await remoteConfig.fetchAndActivate();
}

Future<void> main() async {
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
  Provider.debugCheckInvalidValueType = null;
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();

  try {
    await FirebaseAppCheck.instance.activate(
      providerAndroid: kReleaseMode
          ? const AndroidPlayIntegrityProvider()
          : const AndroidDebugProvider(),
      providerApple: kReleaseMode
          ? const AppleAppAttestProvider()
          : const AppleDebugProvider(),
    );
  } catch (e) {
    _log.severe('Firebase App Check activation failed.', e);
  }

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  await initPurchases();
  await setUpRemoteConfig();
  AdsController? adsController;
  if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
    adsController = AdsController(MobileAds.instance);
  }

  GamesServicesController? gamesServicesController;
  if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
    gamesServicesController = GamesServicesController();
  }

  MoneyController? inAppPurchaseController;
  if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
    inAppPurchaseController = MoneyController();
  }

  FirebaseService firebaseService = FirebaseService();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  runApp(
    MyApp(
        progressPersistence: ProgressPersistence(),
        settingsPersistence: LocalStorageSettingsPersistence(),
        levelPersistence: LocalStorageLevelPersistence(),
        adsController: adsController,
        inAppPurchaseController: inAppPurchaseController,
        gamesServicesController: gamesServicesController,
        firebaseService: firebaseService),
  );
}

Logger _log = Logger('main.dart');


class MyApp extends StatelessWidget {
  final SettingsPersistence settingsPersistence;
  final ProgressPersistence progressPersistence;
  final LevelPersistence levelPersistence;
  final AdsController? adsController;
  final MoneyController? inAppPurchaseController;
  final GamesServicesController? gamesServicesController;
  final FirebaseService firebaseService;

  const MyApp(
      {super.key,
      required this.settingsPersistence,
      required this.progressPersistence,
      required this.levelPersistence,
      required this.adsController,
      required this.inAppPurchaseController,
      required this.gamesServicesController,
      required this.firebaseService});

  @override
  Widget build(BuildContext context) {
    return AppLifecycleObserver(
        child: MultiProvider(
      providers: [
        Provider<ProgressPersistence>.value(
          value: progressPersistence,
        ),
        Provider<FirebaseService>(
          create: (_) => firebaseService,
        ),
        StreamProvider<List<Category>>(
          create: (context) =>
              context.read<FirebaseService>().getCategoriesStream(),
          initialData: [],
        ),
        Provider<SettingsController>(
          lazy: false,
          create: (context) => SettingsController(
            persistence: settingsPersistence,
          )..loadStateFromPersistence(),
        ),
        Provider<GamesServicesController?>.value(
            value: gamesServicesController),
        ChangeNotifierProvider<AdsController?>.value(value: adsController),
        ChangeNotifierProvider<MoneyController?>.value(
            value: inAppPurchaseController),
        ProxyProvider2<SettingsController, ValueNotifier<AppLifecycleState>,
            AudioController>(
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
        ChangeNotifierProxyProvider<ValueNotifier<AppLifecycleState>,
            LevelModel>(
          lazy: false,
          create: (context) => LevelModel(
              gamesServicesController: gamesServicesController,
              persistence: levelPersistence,
              inAppPurchaseController: inAppPurchaseController,
              adsController: adsController,
              progressPersistence: context.read<ProgressPersistence>(),
              settingsPersistence:
                  context.read<SettingsController>().persistence,
              firebaseService: firebaseService,
              // *** FIX: Read the AudioController from the context ***
              audioController: context.read<AudioController>()),
          update: (BuildContext context,
              ValueNotifier<AppLifecycleState> lifecycleNotifier,
              LevelModel? levelModel) {
            if (levelModel == null) throw ArgumentError.notNull();
            levelModel.attachLifecycleNotifier(lifecycleNotifier);
            return levelModel;
          },
        ),
      ],
      builder: (context, child) {
        final settingsController = context.read<SettingsController>();

        return ValueListenableBuilder(
          valueListenable: settingsController.seedColor,
          builder: (context, changingSeedColor, child) {
            SystemChrome.setPreferredOrientations([
              DeviceOrientation.portraitUp,
              DeviceOrientation.portraitDown,
            ]);

            return MaterialApp(
                title: 'Subliminal Words',
                debugShowCheckedModeBanner: false,
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
                  body: GameFieldScreen(),
                ));
          },
        );
      },
    ));
  }
}
