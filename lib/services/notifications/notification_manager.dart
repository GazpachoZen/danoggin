import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:danoggin/services/auth_service.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'base/notification_service.dart';
import 'local/local_notification_service.dart';
import 'local/platform_helper.dart';
import 'fcm/fcm_notification_service.dart';
import 'package:danoggin/utils/logger.dart';

/// Central manager for all notification functionality
class NotificationManager {
  // Singleton instance
  static final NotificationManager _instance = NotificationManager._internal();
  factory NotificationManager() => _instance;

  // Services
  late NotificationService _localService;
  late NotificationService _fcmService;
  final Logger _logger = Logger();

  // Flag to track services that are registered
  final Set<String> _registeredServices = {};

  // Flag to track if permission dialog has been shown this session
  bool _hasShownPermissionDialog = false;

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
    _logger.i('Initializing notification services');
    try {
      // Only initialize local service initially
      await _localService.initialize();
      _logger.i('Local notification service initialized');
    } catch (e) {
      _logger.e('Error initializing local notification service: $e');
    }
  }

  Future<void> initializeFCM() async {
    try {
      _logger.d('Initializing FCM notification service');
      await _fcmService.initialize();
      _logger.i('FCM notification service initialized');
    } catch (e) {
      _logger.e('Error initializing FCM notification service: $e');
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

  /// Check notification permissions and show dialog if needed
  /// Returns true if notifications are enabled
  Future<bool> checkAndRequestPermissions(BuildContext context) async {
    // If we've already shown the dialog this session, don't show again
    if (_hasShownPermissionDialog) {
      return await areNotificationsEnabled();
    }

    bool enabled = true;
    try {
      enabled = await areNotificationsEnabled();
    } catch (e) {
      _logger.e('Error checking notification permissions: $e');
      return false;
    }

    // If notifications are already enabled, return true
    if (enabled) {
      return true;
    }

    // Mark that we've shown the dialog
    _hasShownPermissionDialog = true;

    // Check if we can directly open settings
    bool canOpenSettings = await _canLaunchNotificationSettings();

    // Show permission dialog
    if (context.mounted) {
      await showDialog(
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
                'Notifications are important for alerting you about check-ins.',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Later'),
            ),
            if (canOpenSettings)
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _openNotificationSettings();
                },
                child: Text('Open Settings'),
              ),
          ],
        ),
      );
    }

    // Return current permission status
    return enabled;
  }

  // Check if we can launch notification settings
  Future<bool> _canLaunchNotificationSettings() async {
    try {
      if (Platform.isIOS) {
        return await canLaunchUrl(Uri.parse('app-settings:'));
      } else if (Platform.isAndroid) {
        // For Android, this is more complex and less reliable
        // For simplicity, we'll return true for Android 6.0 and higher
        return true;
      }
      return false;
    } catch (e) {
      _logger.e('Error checking if can launch settings: $e');
      return false;
    }
  }

  // Open notification settings
  Future<void> _openNotificationSettings() async {
    try {
      if (Platform.isIOS) {
        await launchUrl(Uri.parse('app-settings:'));
      } else if (Platform.isAndroid) {
        // Try different approaches for Android
        try {
          // Android 8+
          await launchUrl(Uri.parse('package:com.bluevistas.danoggin'));
        } catch (e) {
          _logger.e('Failed to open app settings: $e');
          // Fallback to app info page on older Android
          await launchUrl(Uri.parse('package:com.bluevistas.danoggin'));
        }
      }
    } catch (e) {
      _logger.e('Error opening notification settings: $e');
    }
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
    _logger.d("useBestNotification called: title=$title, id=$id");

    try {
      // Get platform helper
      final platformHelper = (_localService is LocalNotificationService)
          ? (_localService as LocalNotificationService).platformHelper
          : null;

      // iOS in foreground: Always use in-app notification for consistency
      if (Platform.isIOS &&
          platformHelper != null &&
          !platformHelper.isInBackground) {
        _logger.i("iOS foreground: Using in-app notification");

        // Only show in-app if we have a context
        if (platformHelper.currentContext != null) {
          await _localService.showInAppNotification(
            context: platformHelper.currentContext!,
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
            _logger.i('Emitted notification event for refresh');
          }

          return true;
        } else {
          _logger.w(
              "iOS foreground: No context available, falling back to system notification");
          // Fall through to system notification
        }
      }

      // All other cases: Use system notification
      _logger.i("Using system notification");
      return await _localService.showNotification(
        id: id,
        title: title,
        body: body,
        triggerRefresh: triggerRefresh,
        payload: payload,
      );
    } catch (e) {
      _logger.e('Error in useBestNotification: $e');
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
    _logger.i(message);
  }

  /// Clean up resources
  void dispose() {
    _localService.dispose();
  }

  // Helper shortcut to the platform helper
  PlatformHelper? get platformHelper {
    return (_localService is LocalNotificationService)
        ? (_localService as LocalNotificationService).platformHelper
        : null;
  }

  Future<void> ensureBackgroundNotificationsEnabled() async {
    // This is just an alias for requestPermissions()
    await requestPermissions();
    _logger.i('Background notifications have been configured');
  }

  /// Request notification permissions explicitly
  Future<void> requestNotificationPermissions() async {
    await _localService.requestPermissions();
  }

/// Clear all badges via Cloud Function (works for all platforms)
Future<void> clearIOSBadge() async {
  _logger.i('Clearing badges via Cloud Function');
  
  try {
    final uid = AuthService.currentUserId;
    
    // Call the Cloud Function to clear badge
    final response = await http.post(
      Uri.parse('https://us-central1-danoggin-d0478.cloudfunctions.net/clearUserBadge'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'userId': uid}),
    );
    
    if (response.statusCode == 200) {
      _logger.i('All badges cleared successfully via Cloud Function');
    } else {
      _logger.e('Failed to clear badges: ${response.statusCode}');
    }
  } catch (e) {
    _logger.e('Error clearing badges: $e');
  }
}

  // Deprecated method - kept for backward compatibility
  // but now just redirects to our new implementation
  Future<void> showPermissionDialog(BuildContext context) async {
    _logger.w(
        'showPermissionDialog is deprecated. Using checkAndRequestPermissions instead.');
    await checkAndRequestPermissions(context);
  }

  // Provide access to open notification settings directly
  Future<void> openNotificationSettings(BuildContext context) async {
    await _openNotificationSettings();
  }
}
