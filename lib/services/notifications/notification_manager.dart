import 'dart:io';
import 'package:flutter/material.dart';
import 'base/notification_logger.dart';
import 'base/notification_service.dart';
import 'base/notification_handler.dart'; // Add this import
import 'local/local_notification_service.dart';
import 'local/platform_helper.dart';
import 'fcm/fcm_notification_service.dart';
import 'fcm/fcm_helper.dart';

/// Central manager for all notification functionality
class NotificationManager {
  // Singleton instance
  static final NotificationManager _instance = NotificationManager._internal();
  factory NotificationManager() => _instance;

  // Services
  late NotificationService _localService;
  late NotificationService _fcmService;
  final NotificationLogger _logger = NotificationLogger();

  // Flag to track services that are registered
  final Set<String> _registeredServices = {};

  // Private constructor
  NotificationManager._internal() {
    // Initialize both services directly
    _localService = LocalNotificationService();
    _fcmService = FCMNotificationService();
    _registeredServices.add('local');
    _registeredServices.add('fcm');
  }

  /// Initialize all notification services
  Future<void> initialize() async {
    _logger.log('Initializing notification services');
    try {
      // Only initialize local service initially
      await _localService.initialize();
      _logger.log('Local notification service initialized');
    } catch (e) {
      _logger.log('Error initializing local notification service: $e');
    }
  }

  Future<void> initializeFCM() async {
    try {
      _logger.log('Initializing FCM notification service');
      await _fcmService.initialize();
      _logger.log('FCM notification service initialized');
    } catch (e) {
      _logger.log('Error initializing FCM notification service: $e');
    }
  }

  Future<void> _initFCM() async {
    if (!_registeredServices.contains('fcm')) {
      _fcmService = FCMNotificationService();
      _registeredServices.add('fcm');
      await _fcmService.initialize();
    }
  }

  /// Check if notifications are enabled
  Future<bool> areNotificationsEnabled() async {
    return await _localService.areNotificationsEnabled();
  }

  /// Request notification permissions
  Future<void> requestPermissions() async {
    await _localService.requestPermissions();
  }

  /// Show a notification using the best available method
  Future<bool> useBestNotification({
    required String title,
    required String body,
    dynamic id = 0,
    bool playSound = true,
    bool triggerRefresh = false,
    Map<String, dynamic>? payload,
  }) async {
    _logger.log("useBestNotification called: title=$title, id=$id");

    try {
      // iOS in foreground with context: Use in-app overlay notification
      if (Platform.isIOS &&
          !_platformHelper.isInBackground &&
          _platformHelper.currentContext != null &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        _logger.log("iOS foreground: Using in-app notification");

        await _localService.showInAppNotification(
          context: _platformHelper.currentContext!,
          title: title,
          body: body,
          playSound: playSound,
        );

        // If refresh is needed
        if (triggerRefresh) {
          ((_localService as LocalNotificationService).notificationHandler)
              .addNotificationEvent({
            'id': id,
            'title': title,
            'body': body,
            'payload': payload,
          });
          _logger.log('Emitted notification event for refresh');
        }

        return true;
      }
      // All other cases: Use system notification
      else {
        _logger.log("Using system notification");
        return await _localService.showNotification(
          id: id,
          title: title,
          body: body,
          triggerRefresh: triggerRefresh,
          payload: payload,
        );
      }
    } catch (e) {
      _logger.log('Error in useBestNotification: $e');
      return false;
    }
  }

  /// Show a delayed notification
  Future<bool> showDelayedNotification({
    required String title,
    required String body,
    dynamic id = 0,
    required Duration delay,
    bool triggerRefresh = false,
    Map<String, dynamic>? payload,
  }) async {
    return await _localService.showDelayedNotification(
      id: id,
      title: title,
      body: body,
      delay: delay,
      triggerRefresh: triggerRefresh,
      payload: payload,
    );
  }

  /// Cancel a specific notification
  Future<void> cancelNotification(int id) async {
    await _localService.cancelNotification(id);
  }

  /// Cancel all notifications
  Future<void> cancelAllNotifications() async {
    await _localService.cancelAllNotifications();
  }

  /// Track application lifecycle state
  void trackAppState(AppLifecycleState state) {
    _localService.trackAppState(state);
  }

  /// Set current UI context
  void setCurrentContext(BuildContext? context) {
    _localService.setCurrentContext(context);
  }

  /// Show permission dialog
  Future<void> showPermissionDialog(BuildContext context) async {
    if (_localService is LocalNotificationService) {
      await (_localService as LocalNotificationService)
          .showPermissionDialog(context);
    }
  }

  /// Get notification event stream
  Stream<dynamic> get notificationEvents {
    if (_localService is LocalNotificationService) {
      return (_localService as LocalNotificationService).notificationEvents;
    }

    // Fallback to empty stream if service doesn't support events
    return Stream.empty();
  }

  /// Get all logs
  List<String> get logs => _logger.logs;

  /// Clear all logs
  void clearLogs() {
    _logger.clearLogs();
  }

  /// Log a message
  void log(String message) {
    _logger.log(message);
  }

  /// Clean up resources
  void dispose() {
    _localService.dispose();
  }

  // Helper shortcut to the platform helper
  PlatformHelper get _platformHelper {
    return (_localService as LocalNotificationService).platformHelper;
  }

  void openNotificationSettings(BuildContext context) {
    if (_localService is LocalNotificationService) {
      // Use the public platformHelper accessor we created
      (_localService as LocalNotificationService)
          .platformHelper
          .openNotificationSettings(context);
    }
  }

  Future<void> ensureBackgroundNotificationsEnabled() async {
    // This is just an alias for requestPermissions()
    await requestPermissions();
    _logger.log('Background notifications have been configured');
  }

  /// Request notification permissions explicitly
  Future<void> requestNotificationPermissions() async {
    await _localService.requestPermissions();
  }

  /// Clear the iOS badge (notification count)
  /// Clear the iOS badge (notification count)
  Future<void> clearIOSBadge() async {
    // Only clear badge on iOS
    if (!Platform.isIOS) {
      log('Not iOS - skipping badge clear');
      return;
    }

    log('Clearing iOS badge');
    try {
      if (_localService is LocalNotificationService) {
        // Use the local service to clear the badge
        await _localService.showNotification(
          id: 0,
          title: '',
          body: '',
          triggerRefresh: false,
          payload: {'clearBadgeOnly': 'true'},
        );
      }
    } catch (e) {
      log('Error clearing iOS badge: $e');
    }
  }
}
