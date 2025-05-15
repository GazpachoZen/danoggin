import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:async';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

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

    print('Starting notification helper initialization...');

    // Initialize time zones
    tz_data.initializeTimeZones();

    // Basic Android settings
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // Enhanced iOS settings with explicit foreground delegation
    // Remove 'const' since we're using callbacks which are not const
    final DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      // Add this critical callback for iOS foreground notifications
      notificationCategories: [
        DarwinNotificationCategory(
          'danoggin_category',
          actions: [
            DarwinNotificationAction.plain(
              'view',
              'View',
              options: {DarwinNotificationActionOption.foreground},
            ),
          ],
        ),
      ],
      // Add onDidReceiveLocalNotification for older iOS versions
      onDidReceiveLocalNotification:
          (int id, String? title, String? body, String? payload) async {
        print('Received foreground notification: id=$id, title=$title');
        // Re-emit the notification to our stream to handle it in-app
        _notificationStreamController
            .add({'id': id, 'title': title, 'body': body, 'payload': payload});
      },
    );

    final InitializationSettings initSettings = InitializationSettings(
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

    // For Android, set up notification channel with high importance
    if (Platform.isAndroid) {
      try {
        final androidPlugin =
            _notifications.resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();

        if (androidPlugin != null) {
          // Create a notification channel with high importance
          const AndroidNotificationChannel channel = AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: _channelDescription,
            importance: Importance.high,
          );

          await androidPlugin.createNotificationChannel(channel);
          print('Notification channel created successfully');
        }
      } catch (e) {
        print('Error creating Android notification channel: $e');
        // Continue anyway - older versions may still work without explicit channel creation
      }
    }

    _isInitialized = true;
    print('Notifications initialized successfully');
  }

  /// Check if notifications are enabled
  static Future<bool> areNotificationsEnabled() async {
    if (!_isInitialized) {
      await initialize();
    }

    print('Checking notification permissions...');

    try {
      if (Platform.isAndroid) {
        final androidPlugin =
            _notifications.resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();

        if (androidPlugin == null) return false;

        // Check if notifications are enabled on Android
        try {
          final enabled =
              await androidPlugin.areNotificationsEnabled() ?? false;
          print('Android notification permission status: $enabled');
          return enabled;
        } catch (e) {
          print('Error calling areNotificationsEnabled: $e');
          // Fall back to assuming they're enabled
          return true;
        }
      } else if (Platform.isIOS) {
        // For iOS, we need to explicitly request permissions
        final iosPlugin = _notifications.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();

        final result = await iosPlugin?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );

        print('iOS notification permission request result: $result');
        return result ?? false;
      }

      return false;
    } catch (e) {
      print('Error checking notification permissions: $e');
      return false;
    }
  }

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

      // Enhanced Android notification details for better visibility
      const AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        playSound: true,
        enableVibration: true,
      );

      // iOS notification details with available parameters only
      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'default',
        interruptionLevel: InterruptionLevel.active,
        // Only use parameters that are definitely available
        categoryIdentifier: 'danoggin_category',
      );

      const NotificationDetails platformDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      // Log more information about the notification
      print('Showing notification with following details:');
      print('  ID: $id');
      print('  Title: $title');
      print('  Body: $body');
      if (Platform.isAndroid) {
        print('  Platform: Android');
      } else if (Platform.isIOS) {
        print('  Platform: iOS');
      }

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

  /// iOS-specific test notification method
  static Future<bool> testIOSNotification() async {
    try {
      if (!_isInitialized) {
        await initialize();
      }

      print('Testing iOS notification specifically...');

      // Request permissions explicitly before showing notification
      final iosPlugin = _notifications.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();

      final permGranted = await iosPlugin?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );

      print('iOS permissions request result: $permGranted');

      // Use only available parameters for iOS notification
      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        interruptionLevel: InterruptionLevel.active,
        categoryIdentifier: 'danoggin_category',
      );

      const NotificationDetails details = NotificationDetails(iOS: iosDetails);

      // Generate a unique ID
      final id = DateTime.now().millisecond;

      print('Sending iOS test notification with ID: $id');
      await _notifications.show(
        id,
        'iOS Test Notification',
        'This is a test notification specifically for iOS. It should appear even when the app is in the foreground.',
        details,
      );

      print('iOS test notification sent!');
      return true;
    } catch (e) {
      print('Error showing iOS notification: $e');
      return false;
    }
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
    int sdkVersion = 0;
    if (Platform.isAndroid) {
      sdkVersion = await _getAndroidSdkVersion();
      print('Android SDK version: $sdkVersion');
    }

    bool enabled = false;
    try {
      enabled = await areNotificationsEnabled();
    } catch (e) {
      print('Error checking notification permissions: $e');
    }

    if (!enabled && context.mounted) {
      // Prepare special instructions for Android 13+ (API 33+)
      final String instructions = Platform.isAndroid && sdkVersion >= 33
          ? 'On Android 13 or higher, you will need to explicitly grant notification permission when prompted.'
          : Platform.isIOS
              ? 'On iOS, you need to enable notifications when prompted.'
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
              if (Platform.isAndroid) ...[
                Text('1. Open your device Settings'),
                Text('2. Tap on Apps or Application Manager'),
                Text('3. Find and tap on "Danoggin"'),
                Text('4. Tap on Notifications'),
                Text('5. Enable "Allow notifications"'),
              ] else if (Platform.isIOS) ...[
                Text('1. Open your device Settings'),
                Text('2. Scroll down and tap on "Danoggin"'),
                Text('3. Tap on Notifications'),
                Text('4. Enable "Allow Notifications"'),
              ],
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
            if (Platform.isAndroid) ...[
              Text('1. Open your device Settings'),
              Text('2. Tap on Apps or Application Manager'),
              Text('3. Find and tap on "Danoggin"'),
              Text('4. Tap on Notifications'),
              Text('5. Enable "Allow notifications"'),
            ] else if (Platform.isIOS) ...[
              Text('1. Open your device Settings'),
              Text('2. Scroll down and tap on "Danoggin"'),
              Text('3. Tap on Notifications'),
              Text('4. Enable "Allow Notifications"'),
            ],
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

  // Request notification permissions explicitly
  static Future<void> requestNotificationPermissions() async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      // For Android, permissions are handled through notification channels
      if (Platform.isAndroid) {
        print(
            'Android notification permissions handled through channel creation');
      }

      // For iOS, explicitly request permissions
      if (Platform.isIOS) {
        final iosPlugin = _notifications.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
        if (iosPlugin != null) {
          final result = await iosPlugin.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
          print('iOS notification permission request result: $result');
        }
      }
    } catch (e) {
      print('Error requesting notification permissions: $e');
    }
  }

  // Ensure background notifications are properly configured
  static Future<void> ensureBackgroundNotificationsEnabled() async {
    if (!_isInitialized) {
      await initialize();
    }

    // The notification channel created in initialize() should be sufficient
    // Just make sure permissions are properly requested
    await requestNotificationPermissions();

    print('Background notifications have been configured');
  }

  // Add cleanup method to dispose of the stream controller
  static void dispose() {
    _notificationStreamController.close();
  }

  static Future<bool> testDelayedNotification() async {
    try {
      if (!_isInitialized) {
        await initialize();
      }

      print('Testing delayed notification (3 seconds)...');

      // For iOS, set specific details
      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        interruptionLevel: InterruptionLevel.active,
      );

      // For Android
      const AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.high,
        priority: Priority.high,
        ticker: 'ticker',
      );

      const NotificationDetails details = NotificationDetails(
        iOS: iosDetails,
        android: androidDetails,
      );

      // Generate a unique ID
      final id = DateTime.now().millisecond;

      // Schedule notification for 3 seconds later
      await _notifications.zonedSchedule(
        id,
        'Delayed Test Notification',
        'This notification was delayed by 3 seconds to simulate background behavior',
        tz.TZDateTime.now(tz.local).add(const Duration(seconds: 3)),
        details,
        androidAllowWhileIdle: true,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );

      print('Delayed notification scheduled!');
      return true;
    } catch (e) {
      print('Error scheduling delayed notification: $e');
      return false;
    }
  }

  static Future<bool> testForegroundNotificationiOS() async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      print('Testing basic foreground notification for iOS');

      // Force request permissions again
      if (Platform.isIOS) {
        final iosPlugin = _notifications.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
        await iosPlugin?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
      }

      // Try with absolute minimum configuration
      final id = DateTime.now().millisecond;

      // Create a very basic notification
      if (Platform.isIOS) {
        // For iOS, create a plain notification
        print('Using minimal iOS notification configuration');

        // Using only essential iOS settings
        final details = NotificationDetails(
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
            interruptionLevel: InterruptionLevel.active,
          ),
        );

        // Send the notification
        print('Sending iOS foreground test notification with ID: $id');
        await _notifications.show(
          id,
          'iOS Foreground Test',
          'Basic foreground notification test - ${DateTime.now().toString()}',
          details,
        );
      } else {
        // For Android, use existing configuration
        print('Test called on Android - using standard configuration');
        await showAlert(
          id: id,
          title: 'Android Test',
          body: 'Basic test notification',
          triggerRefresh: false,
        );
      }

      print('Test notification sent with ID: $id');
      return true;
    } catch (e) {
      print('Error in foreground notification test: $e');
      return false;
    }
  }
}
