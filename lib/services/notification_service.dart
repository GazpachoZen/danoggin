// Copyright (c) 2025, Blue Vista Solutions.  All rights reserved.
//
// This source code is part of the Danoggin project and is intended for 
// internal or authorized use only. Unauthorized copying, modification, or 
// distribution of this file, via any medium, is strictly prohibited. For 
// licensing or permissions, contact: ivory@blue-vistas.com
//------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final _notifications = FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    final androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    final initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _notifications.initialize(initSettings);

    tz.initializeTimeZones();
    final localName = await tz.local.name;
    tz.setLocalLocation(tz.getLocation(localName));
  }

  static Future<void> scheduleTestNotification({int delaySeconds = 5}) async {
    final scheduledTime = tz.TZDateTime.now(tz.local).add(Duration(seconds: delaySeconds));

    try {
      await _notifications.zonedSchedule(
        0,
        'Danoggin Alert',
        'This is a scheduled notification.',
        scheduledTime,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'danoggin_channel',
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
      // Fallback for older devices or silent errors
      debugPrint('zonedSchedule failed, falling back to delayed show(): $e');
      Future.delayed(Duration(seconds: delaySeconds), () {
        _notifications.show(
          0,
          'Danoggin Alert',
          'This is a fallback notification.',
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'danoggin_channel',
              'Danoggin Notifications',
              channelDescription: 'Fallback notifications',
              importance: Importance.max,
              priority: Priority.high,
            ),
          ),
        );
      });
    }
  }

    static Future<void> showBasicNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'danoggin_channel',
      'Danoggin Alerts',
      channelDescription: 'Periodic awareness check-ins',
      importance: Importance.high,
      priority: Priority.high,
    );

    const NotificationDetails platformDetails =
        NotificationDetails(android: androidDetails);

    await _notifications.show(
      id,
      title,
      body,
      platformDetails,
    );
  }

}
