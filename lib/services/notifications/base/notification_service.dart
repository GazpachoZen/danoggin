import 'package:flutter/material.dart';

/// Core notification service interface
abstract class NotificationService {
  /// Initialize the notification service
  Future<void> initialize();

  /// Check if notifications are enabled
  Future<bool> areNotificationsEnabled();

  /// Request notification permissions
  Future<void> requestPermissions();

  /// Show a notification
  Future<bool> showNotification({
    required dynamic id,
    required String title, 
    required String body,
    bool triggerRefresh = false,
    Map<String, dynamic>? payload,
  });

  /// Show a notification with a delay
  Future<bool> showDelayedNotification({
    required dynamic id,
    required String title,
    required String body,
    required Duration delay,
    bool triggerRefresh = false,
    Map<String, dynamic>? payload,
  });

  /// Show in-app notification
  Future<void> showInAppNotification({
    required BuildContext context,
    required String title,
    required String body,
    bool playSound = true,
  });

  /// Cancel a specific notification
  Future<void> cancelNotification(int id);

  /// Cancel all notifications
  Future<void> cancelAllNotifications();

  /// Track application lifecycle state
  void trackAppState(AppLifecycleState state);

  /// Set current UI context
  void setCurrentContext(BuildContext? context);

  /// Clean up resources
  void dispose();
}