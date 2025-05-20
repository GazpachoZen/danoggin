import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:danoggin/utils/logger.dart';

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
    _logger.log("Current notification context ${context != null ? 'set' : 'cleared'}");
  }
  
  /// Track application lifecycle state
  void trackAppState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _appInBackground = true;
      _logger.log("App entered background state: $state");
    } else if (state == AppLifecycleState.resumed) {
      _appInBackground = false;
      _logger.log("App entered foreground state: $state");
    } else {
      // For inactive and hidden states, don't change the background flag
      _logger.log("App in transition state: $state (keeping isBackground: $_appInBackground)");
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
          _logger.log('Android notification channel created successfully');
        }
      } catch (e) {
        _logger.log('Error creating Android notification channel: $e');
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
      _logger.log('Error getting Android SDK version: $e');
      return 0;
    }
  }
  
  /// Show platform-specific permission dialog
  Future<void> showPermissionDialog(BuildContext context) async {
    if (_permissionDialogShown) return;
    _permissionDialogShown = true;
    
    int sdkVersion = 0;
    if (Platform.isAndroid) {
      sdkVersion = await getAndroidSdkVersion();
    }
    
    bool enabled = false;
    try {
      // This will need to be updated to call the service's method
      final plugin = _notifications.resolvePlatformSpecificImplementation
          <AndroidFlutterLocalNotificationsPlugin>();
      enabled = await plugin?.areNotificationsEnabled() ?? false;
    } catch (e) {
      _logger.log('Error checking notification permissions: $e');
    }
    
    if (!enabled && context.mounted) {
      final String instructions = Platform.isAndroid && sdkVersion >= 33
          ? 'On Android 13 or higher, you will need to explicitly grant notification permission when prompted.'
          : Platform.isIOS
              ? 'On iOS, you need to enable notifications when prompted.'
              : 'You need to enable notifications in your device settings.';
              
      // Show dialog code (same as in the original file)
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
  
  /// Open notification settings dialog
  void openNotificationSettings(BuildContext context) {
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
            Text('Notifications are important for alerting you to check-in issues.'),
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