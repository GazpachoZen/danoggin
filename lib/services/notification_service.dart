// Copyright (c) 2025, Blue Vista Solutions.  All rights reserved.
//
// This source code is part of the Danoggin project and is intended for
// internal or authorized use only. Unauthorized copying, modification, or
// distribution of this file, via any medium, is strictly prohibited. For
// licensing or permissions, contact: ivory@blue-vistas.com
//------------------------------------------------------------------------

import 'package:danoggin/utils/logger.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:danoggin/services/notifications/notification_manager.dart';

class NotificationService {
  static final _notifications = FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    Logger().i("Initializing notification service...");

    // Android initialization settings
    final androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS initialization settings
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    // Initialize settings for all platforms
    final initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    // Initialize the plugin
    final success = await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        Logger().i("Notification clicked: ${response.id}");
        // Handle notification tap
      },
    );

    Logger().i("Notification initialization result: $success");

    // Initialize timezone data
    tz.initializeTimeZones();
    final locationName = await tz.TZDateTime.now(tz.local).timeZoneName;
    Logger().i("Using timezone: $locationName");

    // In earlier versions of flutter_local_notifications,
    // permissions are handled through channel creation
    Logger().i("Setting up notification channels (which handles permissions)");

    // Create the notification channels
    await _createNotificationChannels();

    Logger().i("Notification service initialization complete");
  }

  static Future<void> _createNotificationChannels() async {
    // Android only
    final androidPlugin = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      // Main notification channel
      await androidPlugin
          .createNotificationChannel(const AndroidNotificationChannel(
        'danoggin_alerts',
        'Danoggin Notifications',
        description: 'Regular check-in reminders',
        importance: Importance.high,
      ));

      // Alerts notification channel (higher priority)
      await androidPlugin
          .createNotificationChannel(const AndroidNotificationChannel(
        'danoggin_alerts',
        'Danoggin Urgent Alerts',
        description: 'Critical alerts for missed or incorrect check-ins',
        importance: Importance.max,
        // For a custom sound, you'd need to add the file to your Android project
        // sound: RawResourceAndroidNotificationSound('notification_sound'),
        enableVibration: true,
        enableLights: true,
      ));

      Logger().i("Notification channels created");
    }
  }

  static Future<void> scheduleTestNotification({int delaySeconds = 5}) async {
    final scheduledTime =
        tz.TZDateTime.now(tz.local).add(Duration(seconds: delaySeconds));

    try {
      // If we can directly schedule it with timezone
      await _notifications.zonedSchedule(
        0,
        'Danoggin Alert',
        'This is a scheduled notification.',
        scheduledTime,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'danoggin_alerts',
            'Danoggin Notifications',
            channelDescription: 'Used for awareness prompts',
            importance: Importance.max,
            priority: Priority.high,
          ),
        ),
        androidAllowWhileIdle: true,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (e) {
      // Fallback using delayed useBestNotification
      Logger().i(
          'zonedSchedule failed, falling back to delayed notification: $e');
      Future.delayed(Duration(seconds: delaySeconds), () async {
        await NotificationManager().useBestNotification(
          id: 0,
          title: 'Danoggin Alert',
          body: 'This is a scheduled notification.',
          triggerRefresh: true,
        );
      });
    }
  }

  static Future<void> showBasicNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    try {
      const AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
        'danoggin_alerts',
        'Danoggin Alerts',
        channelDescription: 'Periodic awareness check-ins',
        importance: Importance.high,
        priority: Priority.high,
        icon: 'ic_stat_notify',
        playSound: true,
        enableVibration: true,
        channelShowBadge: true,
      );

      const NotificationDetails platformDetails =
          NotificationDetails(android: androidDetails);

      // Add debug logging
      Logger().i("⚠️ Showing notification: Title='$title', Body='$body', ID=$id");

      await _notifications.show(
        id,
        title,
        body,
        platformDetails,
      );

      Logger().i("✓ Notification sent successfully");
    } catch (e) {
      Logger().i("❌ Error showing notification: $e");
      // Try a fallback method
      try {
        await NotificationManager().useBestNotification(
          id: id,
          title: title,
          body: body,
          triggerRefresh: true,
        );
      } catch (e2) {
        Logger().i("❌❌ Fallback notification also failed: $e2");
      }
    }
  }
}
