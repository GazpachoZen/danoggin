import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

import '../base/notification_service.dart';
import '../base/notification_handler.dart';
import '../base/notification_logger.dart';
import 'platform_helper.dart';
import 'display_helper.dart';

/// Local notification service implementation
class LocalNotificationService implements NotificationService {
  static final LocalNotificationService _instance =
      LocalNotificationService._internal();
  factory LocalNotificationService() => _instance;

  // Logger and notification plugin
  final NotificationLogger _logger = NotificationLogger();
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  // Helpers
  late PlatformHelper _platformHelper;
  late DisplayHelper _displayHelper;

  // Notification handler
  final NotificationHandler _handler = DefaultNotificationHandler();

  // Initialization flag
  bool _isInitialized = false;

  LocalNotificationService._internal() {
    _platformHelper = PlatformHelper(_notifications);
    _displayHelper = DisplayHelper();
  }

  @override
  Future<void> initialize() async {
    if (_isInitialized) return;

    _logger.log('Starting notification helper initialization...');

    // Initialize time zones
    tz_data.initializeTimeZones();

    // Basic Android settings
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // Basic iOS settings
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
        _logger.log('Notification clicked: ${response.id}');
        // Convert NotificationResponse to a Map
        final Map<String, dynamic> eventData = {
          'id': response.id,
          'payload': response.payload,
          'actionId': response.actionId,
          'notificationResponseType':
              response.notificationResponseType.toString(),
          'input': response.input,
        };
        _handler.addNotificationEvent(eventData);
      },
    );

    // Set up platform-specific channels
    await _platformHelper.initializePlatformChannels();

    _isInitialized = true;
    _logger.log('Notifications initialized successfully');
  }

  @override
  Future<bool> areNotificationsEnabled() async {
    if (!_isInitialized) {
      await initialize();
    }

    _logger.log('Checking notification permissions...');

    try {
      if (Platform.isAndroid) {
        final androidPlugin =
            _notifications.resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();

        if (androidPlugin == null) return false;

        try {
          final enabled =
              await androidPlugin.areNotificationsEnabled() ?? false;
          _logger.log('Android notification permission status: $enabled');
          return enabled;
        } catch (e) {
          _logger.log('Error calling areNotificationsEnabled: $e');
          return true; // Assume enabled on error
        }
      } else if (Platform.isIOS) {
        final iosPlugin = _notifications.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();

        final result = await iosPlugin?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );

        _logger.log('iOS notification permission request result: $result');
        return result ?? false;
      }

      return false;
    } catch (e) {
      _logger.log('Error checking notification permissions: $e');
      return false;
    }
  }

  @override
  Future<void> requestPermissions() async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      if (Platform.isAndroid) {
        _logger.log(
            'Android notification permissions handled through channel creation');
      }

      if (Platform.isIOS) {
        final iosPlugin = _notifications.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();

        if (iosPlugin != null) {
          final result = await iosPlugin.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );

          _logger.log('iOS notification permission request result: $result');
        }
      }
    } catch (e) {
      _logger.log('Error requesting notification permissions: $e');
    }
  }

  @override
  Future<bool> showNotification({
    required dynamic id,
    required String title,
    required String body,
    bool triggerRefresh = false,
    Map<String, dynamic>? payload,
  }) async {
    _logger.log('Attempting to show notification: id=$id, title=$title');

    if (!_isInitialized) {
      await initialize();
    }

    try {
      // Special case: Clear iOS badge only
      if (Platform.isIOS &&
          payload != null &&
          payload['clearBadgeOnly'] == 'true') {
        final iosPlugin = _notifications.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();

        if (iosPlugin != null) {
          await _notifications.show(
            0,
            null,
            null,
            const NotificationDetails(
              iOS: DarwinNotificationDetails(
                presentAlert: false,
                presentBadge: true,
                presentSound: false,
                badgeNumber: 0,
              ),
            ),
          );
          _logger.log('iOS badge cleared');
        }
        return true;
      }

      // Ensure id is a valid 32-bit integer
      int notificationId = _normalizeId(id);

      // Check if notifications are enabled
      final enabled = await areNotificationsEnabled();
      if (!enabled) {
        _logger.log('Notifications are not enabled for this app');
        return false;
      }

      // Special handling for iOS in background
      if (Platform.isIOS && _platformHelper.isInBackground) {
        return await _showIosBackgroundNotification(
          id: notificationId,
          title: title,
          body: body,
          triggerRefresh: triggerRefresh,
        );
      }

      // Regular notification for Android or iOS foreground
      final platformDetails = _platformHelper.getPlatformNotificationDetails();

      await _notifications.show(
        notificationId,
        title,
        body,
        platformDetails,
        payload: payload != null ? payload.toString() : null,
      );

      if (triggerRefresh) {
        _handler.addNotificationEvent({
          'id': notificationId,
          'title': title,
          'body': body,
          'payload': payload,
        });
        _logger.log('Emitted notification event for refresh');
      }

      _logger.log('Notification sent successfully');
      return true;
    } catch (e) {
      _logger.log('Error showing notification: $e');
      return false;
    }
  }

  // Handle iOS background notifications with multiple approaches
  Future<bool> _showIosBackgroundNotification({
    required int id,
    required String title,
    required String body,
    required bool triggerRefresh,
  }) async {
    _logger.log('iOS in background: Using special handling');

    // Try three approaches for iOS background notifications:

    // 1. Normal show method
    try {
      final platformDetails = _platformHelper.getPlatformNotificationDetails(
          isIosBackground: false);
      await _notifications.show(id, title, body, platformDetails);
      _logger.log('iOS background: Sent via show method');
    } catch (e) {
      _logger.log('Error with show method: $e');
    }

    // 2. Scheduled notification with 1-second delay
    try {
      final scheduledTime =
          tz.TZDateTime.now(tz.local).add(const Duration(seconds: 1));
      final platformDetails = _platformHelper.getPlatformNotificationDetails(
          isIosBackground: false);

      await _notifications.zonedSchedule(
        id + 1, // Different ID
        title,
        body,
        scheduledTime,
        platformDetails,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
      _logger.log('iOS background: Scheduled notification for 1 second later');
    } catch (e) {
      _logger.log('Error with scheduled notification: $e');
    }

    // 3. Try with badge update as fallback
    try {
      final platformDetails =
          _platformHelper.getPlatformNotificationDetails(isIosBackground: true);

      await _notifications.show(
        id + 2, // Different ID
        title,
        body,
        platformDetails,
      );
      _logger.log('iOS background: Sent with badge update');
    } catch (e) {
      _logger.log('Error with badge notification: $e');
    }

    // If refresh needed, trigger it anyway
    if (triggerRefresh) {
      _handler.addNotificationEvent({
        'id': id,
        'title': title,
        'body': body,
      });
      _logger.log('Emitted notification event for refresh');
    }

    _logger.log('iOS background: Attempted multiple notification methods');
    return true;
  }

  @override
  Future<bool> showDelayedNotification({
    required dynamic id,
    required String title,
    required String body,
    required Duration delay,
    bool triggerRefresh = false,
    Map<String, dynamic>? payload,
  }) async {
    try {
      if (!_isInitialized) {
        await initialize();
      }

      _logger.log(
          'Scheduling delayed notification for ${delay.inSeconds} seconds...');

      // Normalize ID
      final notificationId = _normalizeId(id);

      // Using the foreground context check from the platform helper
      final inForeground = !_platformHelper.isInBackground &&
          _platformHelper.currentContext != null;

      // If in foreground, schedule in-app notification
      if (inForeground && Platform.isIOS) {
        _logger.log('Scheduling delayed in-app notification');

        // Use a timer for in-app notification
        Future.delayed(delay, () {
          final context = _platformHelper.currentContext;
          if (context != null && context.mounted) {
            _displayHelper.showEnhancedInAppNotification(
              context,
              title,
              body,
            );

            if (triggerRefresh) {
              _handler.addNotificationEvent({
                'id': notificationId,
                'title': title,
                'body': body,
                'payload': payload,
              });
            }
          }
        });

        return true;
      } else {
        // For background or Android, schedule system notification
        _logger.log('Scheduling delayed system notification');

        // Calculate the scheduled time
        final scheduledTime = tz.TZDateTime.now(tz.local).add(delay);

        // Get the platform details
        final platformDetails =
            _platformHelper.getPlatformNotificationDetails();

        // Schedule the notification
        await _notifications.zonedSchedule(
          notificationId,
          title,
          body,
          scheduledTime,
          platformDetails,
          androidAllowWhileIdle: true,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: payload != null ? payload.toString() : null,
        );

        _logger.log('Delayed notification scheduled!');
        return true;
      }
    } catch (e) {
      _logger.log('Error scheduling delayed notification: $e');
      return false;
    }
  }

  @override
  Future<void> showInAppNotification({
    required BuildContext context,
    required String title,
    required String body,
    bool playSound = true,
  }) async {
    // Clear the iOS badge when showing in-app notification
    if (Platform.isIOS) {
      try {
        final iosPlugin = _notifications.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
        if (iosPlugin != null) {
          await iosPlugin.requestPermissions(badge: true);
          // Clear the badge
          await _notifications.show(
            0,
            null,
            null,
            const NotificationDetails(
              iOS: DarwinNotificationDetails(
                presentAlert: false,
                presentBadge: true,
                presentSound: false,
                badgeNumber: 0,
              ),
            ),
          );
        }
      } catch (e) {
        _logger.log('Error clearing iOS badge: $e');
      }
    }

    await _displayHelper.showEnhancedInAppNotification(
      context,
      title,
      body,
      playSound: playSound,
    );
  }

  @override
  Future<void> cancelNotification(int id) async {
    try {
      await _notifications.cancel(id);
      _logger.log('Notification with ID $id canceled');
    } catch (e) {
      _logger.log('Error canceling notification: $e');
    }
  }

  @override
  Future<void> cancelAllNotifications() async {
    try {
      await _notifications.cancelAll();
      _logger.log('All notifications canceled');
    } catch (e) {
      _logger.log('Error canceling all notifications: $e');
    }
  }

  @override
  void trackAppState(AppLifecycleState state) {
    _platformHelper.trackAppState(state);
  }

  @override
  void setCurrentContext(BuildContext? context) {
    _platformHelper.setCurrentContext(context);
  }

  @override
  void dispose() {
    _handler.dispose();
  }

  /// Show permission dialog using platform helper
  Future<void> showPermissionDialog(BuildContext context) async {
    await _platformHelper.showPermissionDialog(context);
  }

  /// Get notification event stream
  Stream<dynamic> get notificationEvents => _handler.notificationEvents;

  // Helper method to normalize ID values
  int _normalizeId(dynamic id) {
    if (id is int) {
      // If it's potentially a large int, constrain it to 32-bit range
      return id % 2147483647; // 2^31 - 1
    } else if (id is String) {
      // If it's a string, hash it to get an integer
      return id.hashCode.abs() % 2147483647;
    } else {
      // For any other type, use a default
      return 1;
    }
  }

  NotificationHandler get notificationHandler => _handler;

  PlatformHelper get platformHelper => _platformHelper;
}
