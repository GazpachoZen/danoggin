import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:async';

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

  /// Initialize the notification plugin
  static Future<void> initialize() async {
    if (_isInitialized) return;

    print('Initializing notifications...');

    // Set up the plugin
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initSettings =
        InitializationSettings(android: androidSettings);

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        print('Notification clicked: ${response.id}');
        // Add this line to broadcast the notification event
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

    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
        
    // Set up the background notification handler
    final androidPlugin = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      androidPlugin.createNotificationChannel(channel).then((_) {
        print('Notification channel created successfully');
      });
    }

    _isInitialized = true;
    print('Notifications initialized successfully');
  }

  /// Check if notifications are enabled in system settings
  static Future<bool> areNotificationsEnabled() async {
    final androidPlugin = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin == null) return false;

    try {
      // If this method exists it will return true/false
      return await androidPlugin.areNotificationsEnabled() ?? false;
    } catch (e) {
      // If the method doesn't exist, we can't check, so assume enabled
      print('Could not check notification permissions: $e');
      return true;
    }
  }

  /// Show notification with high priority
  static Future<void> showAlert({
    required int id,
    required String title,
    required String body,
    bool triggerRefresh = true, // Add this parameter to control when to emit event
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
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
      
      // Only emit the event if triggerRefresh is true
      if (triggerRefresh) {
        _notificationStreamController.add({'id': id, 'title': title, 'body': body});
        print('Emitted notification event for refresh');
      }

      print('Alert notification sent: $title - $body');
    } catch (e) {
      print('Error showing notification: $e');
    }
  }

  /// Test notifications to verify they work
  static Future<void> testNotification() async {
    final id = DateTime.now().millisecond;
    await showAlert(
      id: id,
      title: 'Danoggin Test',
      body:
          'This is a test notification. If you see this, notifications are working!',
    );
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

  /// Show an in-app alert dialog as a backup for system notifications
  static void showInAppAlert(
      BuildContext context, String title, String message, {VoidCallback? onAcknowledge}) {
    showDialog(
      context: context,
      barrierDismissible: false, // Force user to acknowledge
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              if (onAcknowledge != null) {
                onAcknowledge();
              }
            },
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Show a notification permissions dialog
  static Future<void> showPermissionDialog(BuildContext context) async {
    bool enabled = false;

    try {
      enabled = await areNotificationsEnabled();
    } catch (e) {
      print('Error checking notification permissions: $e');
      // If we can't check, don't show the dialog
      return;
    }

    if (!enabled && context.mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Enable Notifications'),
          content: Text('Notifications appear to be disabled for this app. '
              'Notifications are important for alerting you to check-in issues. '
              'Would you like to see instructions for enabling them?'),
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
              child: Text('Show Instructions'),
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