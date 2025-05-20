import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:danoggin/utils/logger.dart';
import 'package:danoggin/services/notifications/notification_manager.dart';

/// Helper for platform-specific notification behaviors
class PlatformHelper {
  final Logger _logger = Logger();
  final FlutterLocalNotificationsPlugin _notifications;
  
  // Channel details for Android
  static const String _channelId = 'danoggin_alerts';
  static const String _channelName = 'Danoggin Alerts';
  static const String _channelDescription = 'Alerts for check-in issues';
  
  // State tracking
  bool _appInBackground = false;
  BuildContext? _currentContext;
  bool _permissionDialogShown = false;
  
  PlatformHelper(this._notifications);

  /// Get the current context
  BuildContext? get currentContext => _currentContext;
  
  /// Check if app is in background
  bool get isInBackground => _appInBackground;
  
  /// Set current context for notifications
  void setCurrentContext(BuildContext? context) {
    _currentContext = context;
    _logger.i("Current notification context ${context != null ? 'set' : 'cleared'}");
  }
  
  /// Track application lifecycle state
  void trackAppState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _appInBackground = true;
      _logger.i("App entered background state: $state");
    } else if (state == AppLifecycleState.resumed) {
      _appInBackground = false;
      _logger.i("App entered foreground state: $state");
    } else {
      // For inactive and hidden states, don't change the background flag
      _logger.i("App in transition state: $state (keeping isBackground: $_appInBackground)");
    }
  }
  
  /// Initialize platform-specific notification channels
  Future<void> initializePlatformChannels() async {
    if (Platform.isAndroid) {
      try {
        final androidPlugin = _notifications.resolvePlatformSpecificImplementation
            <AndroidFlutterLocalNotificationsPlugin>();
        
        if (androidPlugin != null) {
          const AndroidNotificationChannel channel = AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: _channelDescription,
            importance: Importance.high,
          );
          
          await androidPlugin.createNotificationChannel(channel);
          _logger.i('Android notification channel created successfully');
        }
      } catch (e) {
        _logger.e('error creating Android notification channel: $e');
      }
    }
  }
  
  /// Check Android SDK version
  Future<int> getAndroidSdkVersion() async {
    if (!Platform.isAndroid) return 0;
    
    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      return androidInfo.version.sdkInt;
    } catch (e) {
      _logger.e('error getting Android SDK version: $e');
      return 0;
    }
  }
  
  /// Show platform-specific permission dialog
 Future<void> showPermissionDialog(BuildContext context) async {
  // Instead of showing its own dialog, delegate to the NotificationManager
  _logger.i("PlatformHelper: Delegating permission dialog to NotificationManager");
  
  // This will ensure only one dialog is shown during the app session
  await NotificationManager().checkAndRequestPermissions(context);
}
 
  /// Generate platform-specific notification details
  NotificationDetails getPlatformNotificationDetails({bool isIosBackground = false}) {
    // Android notification details
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      playSound: true,
      enableVibration: true,
    );
    
    // iOS notification details
    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: 'default',
      interruptionLevel: InterruptionLevel.active,
    );
    
    // iOS background notification with badge (for better visibility)
    const DarwinNotificationDetails iosBadgeDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: 'default',
      badgeNumber: 1,
    );
    
    return NotificationDetails(
      android: androidDetails,
      iOS: isIosBackground ? iosBadgeDetails : iosDetails,
    );
  }
}