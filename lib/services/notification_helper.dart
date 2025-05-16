import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:async';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:collection';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:audioplayers/audioplayers.dart' as audio;

class NotificationHelper {
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
  static Stream<dynamic> get notificationEventStream =>
      _notificationStreamController.stream;

  // Track permission dialog state
  static bool _permissionDialogShown = false;

  /// Initialize the notification plugin
  static Future<void> initialize() async {
    if (_isInitialized) return;

    log('Starting notification helper initialization...');

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
        log('Notification clicked: ${response.id}');
        _notificationStreamController.add(response);
      },
    );

    // For Android, set up notification channel with high importance
    if (Platform.isAndroid) {
      try {
        final androidPlugin =
            _notifications.resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();

        if (androidPlugin != null) {
          // Create a notification channel with high importance
          const AndroidNotificationChannel channel = AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: _channelDescription,
            importance: Importance.high,
          );

          await androidPlugin.createNotificationChannel(channel);
          log('Notification channel created successfully');
        }
      } catch (e) {
        log('Error creating Android notification channel: $e');
        // Continue anyway - older versions may still work without explicit channel creation
      }
    }

    _isInitialized = true;
    log('Notifications initialized successfully');
  }

  /// Check if notifications are enabled
  static Future<bool> areNotificationsEnabled() async {
    if (!_isInitialized) {
      await initialize();
    }

    log('Checking notification permissions...');

    try {
      if (Platform.isAndroid) {
        final androidPlugin =
            _notifications.resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();

        if (androidPlugin == null) return false;

        // Check if notifications are enabled on Android
        try {
          final enabled =
              await androidPlugin.areNotificationsEnabled() ?? false;
          log('Android notification permission status: $enabled');
          return enabled;
        } catch (e) {
          log('Error calling areNotificationsEnabled: $e');
          // Fall back to assuming they're enabled
          return true;
        }
      } else if (Platform.isIOS) {
        // For iOS, we need to explicitly request permissions
        final iosPlugin = _notifications.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();

        final result = await iosPlugin?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );

        log('iOS notification permission request result: $result');
        return result ?? false;
      }

      return false;
    } catch (e) {
      log('Error checking notification permissions: $e');
      return false;
    }
  }

  /// Show notification with high priority
  static Future<bool> showAlert({
    required int id,
    required String title,
    required String body,
    bool triggerRefresh = true,
  }) async {
    log('Attempting to show notification: id=$id, title=$title');

    if (!_isInitialized) {
      await initialize();
    }

    try {
      // Check if notifications are enabled
      final enabled = await areNotificationsEnabled();
      if (!enabled) {
        log('Notifications are not enabled for this app');
        return false;
      }

      // For iOS background, use scheduled notification with minimal delay
      if (Platform.isIOS && _appInBackground) {
        log('iOS background: Using scheduled notification');

        // Initialize time zones if needed
        tz.TZDateTime.now(tz.local); // Force initialization

        // Schedule the notification 1 second in the future
        final scheduledTime =
            tz.TZDateTime.now(tz.local).add(const Duration(seconds: 1));

        // iOS notification details
        const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          sound: 'default',
          interruptionLevel:
              InterruptionLevel.timeSensitive, // Try this more urgent level
        );

        const NotificationDetails platformDetails = NotificationDetails(
          iOS: iosDetails,
        );

        await _notifications.zonedSchedule(
          id,
          title,
          body,
          scheduledTime,
          platformDetails,
          androidAllowWhileIdle: true,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );

        log('iOS background: Scheduled notification for 1 second later');
        return true;
      }

      // Regular notification for Android or iOS foreground
      // Enhanced Android notification details
      const AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
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

      const NotificationDetails platformDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _notifications.show(
        id,
        title,
        body,
        platformDetails,
      );

      if (triggerRefresh) {
        _notificationStreamController
            .add({'id': id, 'title': title, 'body': body});
        log('Emitted notification event for refresh');
      }

      log('Alert notification sent successfully');
      return true;
    } catch (e) {
      log('Error showing notification: $e');
      return false;
    }
  }

  /// Test notifications to verify they work
  /// Test notifications to verify they work
  static Future<bool> testNotification() async {
    final id = DateTime.now().millisecond;

    // For iOS, if we have a context and the app is in foreground, use in-app notification
    if (Platform.isIOS && _currentContext != null && !_appInBackground) {
      log('Using in-app notification for iOS test');
      showEnhancedInAppNotification(
        _currentContext!,
        'Danoggin Test',
        'This is a test notification. If you see this, notifications are working!',
      );
      return true;
    } else {
      // For Android or iOS background, use standard system notification
      log('Using system notification for test (Android or iOS background)');
      return await showAlert(
        id: id,
        title: 'Danoggin Test',
        body:
            'This is a test notification. If you see this, notifications are working!',
      );
    }
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
    // Don't show multiple times
    if (_permissionDialogShown) return;
    _permissionDialogShown = true;

    // Check current Android version
    int sdkVersion = 0;
    if (Platform.isAndroid) {
      sdkVersion = await _getAndroidSdkVersion();
      log('Android SDK version: $sdkVersion');
    }

    bool enabled = false;
    try {
      enabled = await areNotificationsEnabled();
    } catch (e) {
      log('Error checking notification permissions: $e');
    }

    if (!enabled && context.mounted) {
      // Prepare special instructions for Android 13+ (API 33+)
      final String instructions = Platform.isAndroid && sdkVersion >= 33
          ? 'On Android 13 or higher, you will need to explicitly grant notification permission when prompted.'
          : Platform.isIOS
              ? 'On iOS, you need to enable notifications when prompted.'
              : 'You need to enable notifications in your device settings.';

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

  // Request notification permissions explicitly
  static Future<void> requestNotificationPermissions() async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      // For Android, permissions are handled through notification channels
      if (Platform.isAndroid) {
        log('Android notification permissions handled through channel creation');
      }

      // For iOS, explicitly request permissions
      if (Platform.isIOS) {
        final iosPlugin = _notifications.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
        if (iosPlugin != null) {
          final result = await iosPlugin.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
          log('iOS notification permission request result: $result');
        }
      }
    } catch (e) {
      log('Error requesting notification permissions: $e');
    }
  }

  // Ensure background notifications are properly configured
  static Future<void> ensureBackgroundNotificationsEnabled() async {
    if (!_isInitialized) {
      await initialize();
    }

    // Just make sure permissions are properly requested
    await requestNotificationPermissions();
    log('Background notifications have been configured');
  }

  // Add cleanup method to dispose of the stream controller
  static void dispose() {
    _notificationStreamController.close();
  }

  // Delayed notification test method
  static Future<bool> testDelayedNotification() async {
    try {
      if (!_isInitialized) {
        await initialize();
      }

      log('Testing delayed notification (3 seconds)...');

      // Generate a unique ID
      final id = DateTime.now().millisecond;

      // Create a time 3 seconds in the future
      final scheduledTime =
          tz.TZDateTime.now(tz.local).add(const Duration(seconds: 3));

      // If we have a context, schedule a delayed in-app notification
      if (_currentContext != null && !_appInBackground) {
        log('Scheduling delayed in-app notification');
        // Use a timer to show the in-app notification after delay
        Future.delayed(Duration(seconds: 3), () {
          if (_currentContext != null && _currentContext!.mounted) {
            showEnhancedInAppNotification(
              _currentContext!,
              'Delayed Test Notification',
              'This is a delayed in-app notification that appears even when the app is in the foreground',
            );
          }
        });
        return true;
      } else {
        // For background or when no context is available, use system notification
        log('Scheduling delayed system notification');

        // For iOS, set specific details
        const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          interruptionLevel: InterruptionLevel.active,
        );

        // For Android
        const AndroidNotificationDetails androidDetails =
            AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.high,
          priority: Priority.high,
          ticker: 'ticker',
        );

        const NotificationDetails details = NotificationDetails(
          iOS: iosDetails,
          android: androidDetails,
        );

        // Schedule notification
        await _notifications.zonedSchedule(
          id,
          'Delayed Test Notification',
          'This notification was delayed by 3 seconds to simulate background behavior',
          scheduledTime,
          details,
          androidAllowWhileIdle: true,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      }

      log('Delayed notification scheduled!');
      return true;
    } catch (e) {
      log('Error scheduling delayed notification: $e');
      return false;
    }
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
    // More explicit tracking of background state for iOS
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _appInBackground = true;
      log("App entered background state: $state");
    } else if (state == AppLifecycleState.resumed) {
      _appInBackground = false;
      log("App entered foreground state: $state");
    } else {
      // For inactive and hidden states, don't change the background flag
      // This preserves the background state for iOS
      log("App in transition state: $state (keeping isBackground: $_appInBackground)");
    }
  }

  // Set current context for notifications
  static void setCurrentContext(BuildContext? context) {
    _currentContext = context;
    log("Current notification context ${context != null ? 'set' : 'cleared'}");
  }

  // Logging system
  static void log(String message) {
    final timestamp = DateTime.now().toString().substring(0, 19);
    final logMessage = "$timestamp: $message";
    print(logMessage);

    // Add to our queue with a maximum size
    _logMessages.add(logMessage);
    while (_logMessages.length > _maxLogMessages) {
      _logMessages.removeFirst();
    }
  }

  static List<String> get logs => List.from(_logMessages);

  static void clearLogs() {
    _logMessages.clear();
  }

  /// Central notification method that chooses the best way to present a notification
  /// based on platform and app state
  static Future<bool> useBestNotification({
    required String title,
    required String body,
    dynamic id = 0, // Change type to dynamic to handle different input types
    bool playSound = true,
    bool triggerRefresh = false,
    Map<String, dynamic>? payload,
  }) async {
    log("useBestNotification called: title=$title, id=$id");

    try {
      // Ensure id is a valid 32-bit integer
      int notificationId;
      if (id is int) {
        // If it's potentially a large int, constrain it to 32-bit range
        notificationId = id % 2147483647; // 2^31 - 1
      } else if (id is String) {
        // If it's a string, hash it to get an integer
        notificationId = id.hashCode.abs() % 2147483647;
      } else {
        // For any other type, use a default
        notificationId = 1;
      }

      log("Using notification ID: $notificationId (original: $id)");

      // Check if notifications are enabled
      bool enabled = true;
      try {
        enabled = await areNotificationsEnabled();
      } catch (e) {
        log('Error checking notification permissions: $e');
        // Continue with best effort
      }

      if (!enabled) {
        log('Notifications are not enabled for this app');
        return false;
      }

      // iOS in foreground: Use in-app overlay notification
      if (Platform.isIOS &&
          !_appInBackground &&
          _currentContext != null &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        // Double-check we're truly in foreground
        log("Using in-app notification for iOS in foreground (confirmed)");
        await showEnhancedInAppNotification(_currentContext!, title, body,
            playSound: playSound);

        // If a refresh is required, trigger event
        if (triggerRefresh) {
          _notificationStreamController.add({
            'id': notificationId,
            'title': title,
            'body': body,
            'payload': payload
          });
          log('Emitted notification event for refresh');
        }

        return true;
      }
      // All other cases: Use system notification
      else {
        log("Using system notification (Android or iOS background)");
        return await showAlert(
          id: notificationId, // Use the converted ID
          title: title,
          body: body,
          triggerRefresh: triggerRefresh,
        );
      }
    } catch (e) {
      log('Error in useBestNotification: $e');
      return false;
    }
  }
}
