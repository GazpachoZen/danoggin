import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:async';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:collection';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:audioplayers/audioplayers.dart' as audio;
import 'package:flutter/material.dart';
import 'package:danoggin/services/notifications/notification_manager.dart';

class NotificationHelper {
  static final NotificationManager _manager = NotificationManager();

  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static bool _isInitialized = false;
  static const String _channelId = 'danoggin_alerts';
  static const String _channelName = 'Danoggin Alerts';
  static const String _channelDescription = 'Alerts for check-in issues';

  // Logging system
  static final Queue<String> _logMessages = Queue<String>();
  static const int _maxLogMessages = 100;

  // App state tracking
  static bool _appInBackground = false;
  static BuildContext? _currentContext;

  // Add a stream controller for notification events
  static final StreamController<dynamic> _notificationStreamController =
      StreamController<dynamic>.broadcast();

  // Expose the stream
  static Stream<dynamic> get notificationEventStream {
    return _manager.notificationEvents;
  }

  // Track permission dialog state
  static bool _permissionDialogShown = false;

  /// Initialize the notification plugin
  static Future<void> initialize() async {
    await _manager.initialize();
  }

  /// Check if notifications are enabled
  static Future<bool> areNotificationsEnabled() async {
    return await _manager.areNotificationsEnabled();
  }

  /// Show notification with high priority
  static Future<bool> showAlert({
    required int id,
    required String title,
    required String body,
    bool triggerRefresh = true,
  }) async {
    return await _manager.useBestNotification(
      id: id,
      title: title,
      body: body,
      triggerRefresh: triggerRefresh,
    );
  }

  /// Cancel/remove a specific notification by ID
  static Future<void> cancelNotification(int id) async {
    try {
      await _notifications.cancel(id);
      log('Notification with ID $id canceled');
    } catch (e) {
      log('Error canceling notification: $e');
    }
  }

  /// Cancel all notifications
  static Future<void> cancelAllNotifications() async {
    try {
      await _notifications.cancelAll();
      log('All notifications canceled');
    } catch (e) {
      log('Error canceling all notifications: $e');
    }
  }

  /// Check Android SDK version
  static Future<int> _getAndroidSdkVersion() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      return androidInfo.version.sdkInt;
    } catch (e) {
      log('Error getting Android SDK version: $e');
      return 0; // Default to 0 if can't determine
    }
  }

  /// Show a notification permissions dialog
  static Future<void> showPermissionDialog(BuildContext context) async {
    await _manager.showPermissionDialog(context);
  }

  static void openNotificationSettings(BuildContext context) {
    // Delegate to appropriate code
    _manager.showPermissionDialog(context);
  }

  // Request notification permissions explicitly
  static Future<void> requestNotificationPermissions() async {
    await _manager.requestPermissions();
  }

  // Ensure background notifications are properly configured
  static Future<void> ensureBackgroundNotificationsEnabled() async {
    await _manager.requestPermissions();
  }

  // Add cleanup method to dispose of the stream controller
  static void dispose() {
    _manager.dispose();
  }

  // Delayed notification test method
  static Future<bool> testDelayedNotification() async {
    return await _manager.showDelayedNotification(
      id: DateTime.now().millisecond,
      title: 'Delayed Test Notification',
      body: 'This notification was delayed by 3 seconds',
      delay: Duration(seconds: 3),
      triggerRefresh: true,
    );
  }

  // Enhanced in-app notification
  static Future<void> showEnhancedInAppNotification(
      BuildContext context, String title, String body,
      {bool playSound = true}) async {
    log("Showing in-app notification: $title");

    // Play notification sound
    if (playSound) {
      try {
        final player = audio.AudioPlayer();
        await player.play(audio.AssetSource('sounds/notification_sound.mp3'));
      } catch (e) {
        log("Error playing notification sound: $e");
      }
    }

    // First declare the variable without initializing it
    late OverlayEntry entry;

    // Then define the entry
    entry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 10,
        left: 10,
        right: 10,
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue[100],
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.blue[700]!, width: 2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(Icons.notification_important, color: Colors.blue[700]),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.blue[900],
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Text(
                  body,
                  style: TextStyle(fontSize: 14),
                ),
                SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    child: Text('DISMISS'),
                    onPressed: () {
                      entry.remove();
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // Insert the overlay
    Overlay.of(context).insert(entry);

    // Remove after a delay (longer for more attention)
    Future.delayed(Duration(seconds: 8), () {
      try {
        if (context.mounted) {
          entry.remove();
        }
      } catch (e) {
        log("Error removing notification overlay: $e");
      }
    });
  }

  // App state tracking
  static void trackAppState(AppLifecycleState state) {
    _manager.trackAppState(state);
  }
  
  static void setCurrentContext(BuildContext? context) {
    _manager.setCurrentContext(context);
  }
  
  // Logging system
  static void log(String message) {
    _manager.log(message);
  }

  static List<String> get logs => _manager.logs;
  
  static void clearLogs() {
    _manager.clearLogs();
  }

  /// Central notification method that chooses the best way to present a notification
  /// based on platform and app state
  static Future<bool> useBestNotification({
    required String title,
    required String body,
    dynamic id = 0,
    bool playSound = true,
    bool triggerRefresh = false,
    Map<String, dynamic>? payload,
  }) async {
    return await _manager.useBestNotification(
      title: title,
      body: body,
      id: id,
      playSound: playSound,
      triggerRefresh: triggerRefresh,
      payload: payload,
    );
  }


}
