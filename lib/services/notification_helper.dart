import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:async';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_app_check/firebase_app_check.dart';

class NotificationHelper {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static bool _isInitialized = false;
  static const String _channelId = 'danoggin_alerts';
  static const String _channelName = 'Danoggin Alerts';
  static const String _channelDescription = 'Alerts for check-in issues';

  // Add a stream controller for notification events
  static final StreamController<dynamic> _notificationStreamController =
      StreamController<dynamic>.broadcast();

  // Expose the stream
  static Stream<dynamic> get notificationEventStream =>
      _notificationStreamController.stream;

  // Track permission dialog state
  static bool _permissionDialogShown = false;

  /// Initialize the notification plugin
  static Future<void> initialize() async {
    if (_isInitialized) return;

    print('Initializing notifications...');

    print('Starting notification helper initialization...');

    // IMPORTANT: Add this check to prevent auto-initialization of Firebase
    try {
      // This tells Firebase plugins NOT to auto-initialize Firebase
      await FirebaseAppCheck.instance
          .activate(androidProvider: AndroidProvider.debug);
    } catch (e) {
      print('Error during Firebase auto-init prevention: $e');
      // Continue regardless
    }

    // Set up the plugin
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        print('Notification clicked: ${response.id}');
        _notificationStreamController.add(response);
      },
    );

    // Create the notification channel
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDescription,
      importance: Importance.high,
    );

    final androidPlugin = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(channel);
      print('Notification channel created successfully');
    }

    _isInitialized = true;
    print('Notifications initialized successfully');
  }

  /// Check if notifications are enabled in system settings
  static Future<bool> areNotificationsEnabled() async {
    if (!_isInitialized) {
      await initialize();
    }

    final androidPlugin = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin == null) return false;

    try {
      // Check if notifications are enabled
      final enabled = await androidPlugin.areNotificationsEnabled() ?? false;
      print('Notification permission status: $enabled');
      return enabled;
    } catch (e) {
      print('Error checking notification permissions: $e');
      return false;
    }
  }

  /// Show notification with high priority
  static Future<bool> showAlert({
    required int id,
    required String title,
    required String body,
    bool triggerRefresh = true,
  }) async {
    print('Attempting to show notification: id=$id, title=$title');

    if (!_isInitialized) {
      await initialize();
    }

    try {
      // Check if notifications are enabled
      final enabled = await areNotificationsEnabled();
      if (!enabled) {
        print('Notifications are not enabled for this app');
        return false;
      }

      const AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
      );

      const NotificationDetails platformDetails =
          NotificationDetails(android: androidDetails);

      await _notifications.show(
        id,
        title,
        body,
        platformDetails,
      );

      if (triggerRefresh) {
        _notificationStreamController
            .add({'id': id, 'title': title, 'body': body});
        print('Emitted notification event for refresh');
      }

      print('Alert notification sent successfully');
      return true;
    } catch (e) {
      print('Error showing notification: $e');
      return false;
    }
  }

  /// Test notifications to verify they work
  static Future<bool> testNotification() async {
    final id = DateTime.now().millisecond;
    final result = await showAlert(
      id: id,
      title: 'Danoggin Test',
      body:
          'This is a test notification. If you see this, notifications are working!',
    );

    print('Test notification result: $result');
    return result;
  }

  /// Cancel/remove a specific notification by ID
  static Future<void> cancelNotification(int id) async {
    try {
      await _notifications.cancel(id);
      print('Notification with ID $id canceled');
    } catch (e) {
      print('Error canceling notification: $e');
    }
  }

  /// Cancel all notifications
  static Future<void> cancelAllNotifications() async {
    try {
      await _notifications.cancelAll();
      print('All notifications canceled');
    } catch (e) {
      print('Error canceling all notifications: $e');
    }
  }

  /// Check Android SDK version
  static Future<int> _getAndroidSdkVersion() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      return androidInfo.version.sdkInt;
    } catch (e) {
      print('Error getting Android SDK version: $e');
      return 0; // Default to 0 if can't determine
    }
  }

  /// Show a notification permissions dialog
  static Future<void> showPermissionDialog(BuildContext context) async {
    // Don't show multiple times
    if (_permissionDialogShown) return;
    _permissionDialogShown = true;

    // Check current Android version
    final sdkVersion = await _getAndroidSdkVersion();
    print('Android SDK version: $sdkVersion');

    bool enabled = false;
    try {
      enabled = await areNotificationsEnabled();
    } catch (e) {
      print('Error checking notification permissions: $e');
    }

    if (!enabled && context.mounted) {
      // Prepare special instructions for Android 13+ (API 33+)
      final String instructions = sdkVersion >= 33
          ? 'On Android 13 or higher, you will need to explicitly grant notification permission when prompted.'
          : 'You need to enable notifications in your device settings.';

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Enable Notifications'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Danoggin requires notifications to function properly.',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(instructions),
              SizedBox(height: 12),
              Text('To enable notifications for Danoggin:'),
              SizedBox(height: 8),
              Text('1. Open your device Settings'),
              Text('2. Tap on Apps or Application Manager'),
              Text('3. Find and tap on "Danoggin"'),
              Text('4. Tap on Notifications'),
              Text('5. Enable "Allow notifications"'),
              SizedBox(height: 12),
              Text(
                'After enabling notifications, return to the app and tap the "Test Notifications" button in the app bar.',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Later'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                openNotificationSettings(context);
              },
              child: Text('Show Settings Instructions'),
            ),
          ],
        ),
      );
    }
  }

  static void openNotificationSettings(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Enable Notifications'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'To enable notifications for Danoggin, please follow these steps:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
            Text('1. Open your device Settings'),
            Text('2. Tap on Apps or Application Manager'),
            Text('3. Find and tap on "Danoggin"'),
            Text('4. Tap on Notifications'),
            Text('5. Enable "Allow notifications"'),
            SizedBox(height: 10),
            Text(
                'Notifications are important for alerting you to check-in issues.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  // Add cleanup method to dispose of the stream controller
  static void dispose() {
    _notificationStreamController.close();
  }
}
