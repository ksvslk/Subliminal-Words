import 'dart:io';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:google_api_availability/google_api_availability.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:logging/logging.dart';
import 'package:operation_hermes/config/C.dart';
import 'package:operation_hermes/controller/ads_controller.dart';
import 'package:operation_hermes/controller/competition_controller.dart';
import 'package:operation_hermes/controller/money_controller.dart';
import 'package:operation_hermes/ui/screen/game_field_screen.dart';
import 'package:operation_hermes/change_notifier/level_model.dart';
import 'package:operation_hermes/controller/games_services.dart';
import 'package:operation_hermes/controller/firebase_service.dart';
import 'package:operation_hermes/persistence/level_persistence.dart';
import 'package:operation_hermes/persistence/progress_persistence.dart';
import 'package:operation_hermes/persistence/local_storage_level_persistence.dart';
import 'package:operation_hermes/controller/notification_controller.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';
import 'dart:developer' as dev;
import 'persistence/settings_persistence.dart';
import 'persistence/local_storage_settings_persistence.dart';
import 'app_lifecycle.dart';
import 'package:provider/provider.dart';
import 'controller/settings_controller.dart';
import 'controller/audio_controller.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:operation_hermes/data/category.dart';

final LocalStorageLevelPersistence globalLevelPersistence =
    LocalStorageLevelPersistence();

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // If you're going to use other Firebase services in the background, such as Firestore,
  // make sure you call `initializeApp` before using other Firebase services.
  await Firebase.initializeApp();
  //globalLevelPersistence.tryAddingNotificationLevel(message);
}

Future<void> initPurchases() async {
  await Purchases.setLogLevel(LogLevel.verbose);
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
      minimumFetchInterval: const Duration(seconds: 30) // TODO: 6 hours production,
    ),
  );
  await remoteConfig.setDefaults(const {
    C.progressAchievemetns: "",
  });
  remoteConfig.onConfigUpdated.listen((event) async {
    await remoteConfig.activate();
  });
  await remoteConfig.fetchAndActivate();
}

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
  Provider.debugCheckInvalidValueType = null;
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase first.
  await Firebase.initializeApp();

  // Check for an active internet connection.
  final connectivityResult = await (Connectivity().checkConnectivity());
  final isOnline = connectivityResult.contains(ConnectivityResult.mobile) ||
      connectivityResult.contains(ConnectivityResult.wifi);

  // IMPORTANT: Only activate App Check if the device is online.
  // Attempting to activate App Check offline will block the app's startup.
  if (isOnline) {
    try {
      _log.info('Device is online, activating Firebase App Check.');

      await FirebaseAppCheck.instance
          .activate(
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
  } else {
    _log.warning(
        'Device is offline. Skipping Firebase App Check activation to allow offline startup.');
    // CRITICAL: Explicitly disable Firestore network to prevent the SDK
    // from blocking the main thread with connection retries.
    FirebaseFirestore.instance.disableNetwork();
  }

  _log.info('Going full screen');
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  await initPurchases();
  await setUpRemoteConfig();

  AdsController? adsController;
  if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
    /// Prepare the google_mobile_ads plugin so that the first ad loads
    /// faster. This can be done later or with a delay if startup
    /// experience suffers.
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
  CompetitionController? competitionController;
  if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
    competitionController = CompetitionController();
  }
  FirebaseService firebaseService;
  firebaseService = FirebaseService();

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  runApp(
    MyApp(
        progressPersistence: ProgressPersistence(),
        settingsPersistence: LocalStorageSettingsPersistence(),
        levelPersistence: globalLevelPersistence,
        adsController: adsController,
        inAppPurchaseController: inAppPurchaseController,
        gamesServicesController: gamesServicesController,
        competitionController: competitionController,
        firebaseService: firebaseService,
        isOnline: isOnline),
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
  final ProgressPersistence progressPersistence;
  final LevelPersistence levelPersistence;
  final AdsController? adsController;
  final MoneyController? inAppPurchaseController;
  final GamesServicesController? gamesServicesController;
  final CompetitionController? competitionController;
  final FirebaseService firebaseService;
  final bool isOnline;

  const MyApp(
      {super.key,
      required this.settingsPersistence,
      required this.progressPersistence,
      required this.levelPersistence,
      required this.adsController,
      required this.inAppPurchaseController,
      required this.gamesServicesController,
      required this.competitionController,
      required this.firebaseService,
      required this.isOnline});

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
          // 💡 2. ADD initialData. This is required.
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
        Provider<CompetitionController?>.value(value: competitionController),
        ChangeNotifierProvider<MoneyController?>.value(
            value: inAppPurchaseController),
        ChangeNotifierProxyProvider<ValueNotifier<AppLifecycleState>,
            LevelModel>(
          lazy: false,
          create: (context) => LevelModel(
              competitionController: competitionController,
              gamesServicesController: gamesServicesController,
              persistence: levelPersistence,
              inAppPurchaseController: inAppPurchaseController,
              adsController: adsController,
              progressPersistence: context.read<ProgressPersistence>(),
              settingsPersistence:
                  context.read<SettingsController>().persistence,
              firebaseService: firebaseService,
              isOnline: isOnline,
              audioController: null),
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
        ProxyProvider2<SettingsController, ValueNotifier<AppLifecycleState>,
            NotificationController>(
          lazy: false,
          create: (context) => NotificationController()..initialize(),
          update: (context, settings, lifecycleNotifier, nc) {
            if (nc == null) throw ArgumentError.notNull();
            nc.attachSettings(settings);
            return nc;
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
