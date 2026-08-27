import 'dart:io';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:logging/logging.dart';
import 'package:operation_hermes/config/C.dart';
import 'package:operation_hermes/controller/ads_controller.dart';
import 'package:operation_hermes/controller/money_controller.dart';
import 'package:operation_hermes/controller/local_notification_service.dart';
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
import 'package:operation_hermes/ui/app_scaffold_messenger.dart';


@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

/// Stagenator code-gift pushes carry a claimUrl in their data payload. Open it
/// on tap from any app state. Same pattern as AI Movie Quiz: native intent
/// capture closes the engine-boot race; a persisted consumed-message-id set
/// (native) plus a session set and URL window (here) prevent replays and
/// double-opens.
void _handleClaimUrlTaps() {
  String? lastUrl;
  DateTime? lastAt;
  const nativeGuard = MethodChannel('stagenator/claim');
  final sessionIds = <String>{};
  Future<void> open(RemoteMessage? message) async {
    final id = message?.messageId;
    if (id != null) {
      if (!sessionIds.add(id)) return;
      bool fresh = true;
      try {
        fresh = await nativeGuard.invokeMethod<bool>('consume', id) ?? true;
      } catch (_) {
        // iOS / channel unavailable: session set + URL window suffice
      }
      if (!fresh) return;
    }
    final url = message?.data['claimUrl'];
    if (url is String && url.startsWith('https://')) {
      final now = DateTime.now();
      if (url == lastUrl &&
          lastAt != null &&
          now.difference(lastAt!) < const Duration(seconds: 15)) {
        return;
      }
      lastUrl = url;
      lastAt = now;
      try {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } catch (e) {
        debugPrint('claimUrl launch failed: $e');
      }
    }
  }

  Future<void> openRaw(dynamic url) async {
    if (url is String) {
      await open(RemoteMessage(data: {'claimUrl': url}));
    }
  }

  nativeGuard.setMethodCallHandler((call) async {
    if (call.method == 'claimUrl') await openRaw(call.arguments);
  });
  nativeGuard
      .invokeMethod<String>('getPendingClaimUrl')
      .then(openRaw)
      .catchError((_) => null);

  FirebaseMessaging.instance.getInitialMessage().then(open);
  FirebaseMessaging.onMessageOpenedApp.listen(open);
}

class _OnResume extends WidgetsBindingObserver {
  _OnResume(this.onResume);
  final void Function() onResume;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResume();
  }
}

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
  if (kDebugMode) {
    Logger.root.level = Level.ALL;
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
  } else {
    Logger.root.level = Level.WARNING;
  }
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

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

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
  final localNotificationService = LocalNotificationService();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  _handleClaimUrlTaps();
  // Tier-1 identity: tag analytics with the pseudonymous auth uid (no PII)
  // whenever a sign-in lands.
  FirebaseAuth.instance.authStateChanges().listen((user) {
    if (user != null) {
      FirebaseAnalytics.instance
          .setUserId(id: user.uid)
          .catchError((_) {});
    }
  });
  // Keep "last seen" honest for long-lived processes (hourly throttle).
  DateTime? lastTouch;
  WidgetsBinding.instance.addObserver(
    _OnResume(() {
      final now = DateTime.now();
      if (lastTouch != null &&
          now.difference(lastTouch!) < const Duration(hours: 1)) {
        return;
      }
      lastTouch = now;
      FirebaseMessaging.instance.getToken().then((t) {
        if (t != null) firebaseService.savePushToken(t).catchError((_) {});
      });
    }),
  );
  await localNotificationService.initialize();

  runApp(
    MyApp(
        progressPersistence: ProgressPersistence(),
        settingsPersistence: LocalStorageSettingsPersistence(),
        levelPersistence: LocalStorageLevelPersistence(),
        adsController: adsController,
        inAppPurchaseController: inAppPurchaseController,
        gamesServicesController: gamesServicesController,
        firebaseService: firebaseService,
        localNotificationService: localNotificationService),
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
  final LocalNotificationService localNotificationService;

  const MyApp(
      {super.key,
      required this.settingsPersistence,
      required this.progressPersistence,
      required this.levelPersistence,
      required this.adsController,
      required this.inAppPurchaseController,
      required this.gamesServicesController,
      required this.firebaseService,
      required this.localNotificationService});

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
          initialData: const [],
          catchError: (_, error) {
            _log.warning('Could not fetch categories stream (App Check restricted?): $error');
            return <Category>[];
          },
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
              localNotificationService: localNotificationService,
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
                navigatorKey: rootNavigatorKey,
                title: 'Subliminal Words',
                debugShowCheckedModeBanner: false,
                scaffoldMessengerKey: rootScaffoldMessengerKey,
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
                initialRoute: '/',
                routes: {
                  '/': (context) => const Scaffold(body: GameFieldScreen()),
                },
              );
          },
        );
      },
    ));
  }
}
