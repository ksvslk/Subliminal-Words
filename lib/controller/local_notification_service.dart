import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:logging/logging.dart';

class LocalNotificationService {
  static const AndroidNotificationChannel _creatorReviewChannel =
      AndroidNotificationChannel(
    'creator_review_updates',
    'Creator Review Updates',
    description: 'Notifications about user-created level review outcomes.',
    importance: Importance.high,
  );

  static const int _rejectedSubmissionNotificationId = 7001;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static final Logger _log = Logger('LocalNotificationService');

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    const androidSettings =
        AndroidInitializationSettings('@mipmap/launcher_icon');
    const darwinSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
    );

    await _plugin.initialize(settings);
    final androidImplementation =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidImplementation?.createNotificationChannel(
      _creatorReviewChannel,
    );

    _initialized = true;
  }

  Future<void> showRejectedSubmissionNotification({
    required String title,
    required String body,
  }) async {
    try {
      await initialize();
      await _plugin.show(
        _rejectedSubmissionNotificationId,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _creatorReviewChannel.id,
            _creatorReviewChannel.name,
            channelDescription: _creatorReviewChannel.description,
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.status,
            ticker: 'Subliminal Words',
            visibility: NotificationVisibility.public,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentBanner: true,
            presentList: true,
            presentSound: true,
          ),
        ),
      );
    } catch (error, stackTrace) {
      _log.warning(
        'Could not show local rejected-submission notification.',
        error,
        stackTrace,
      );
      rethrow;
    }
  }
}
