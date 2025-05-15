import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:async';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:collection';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:audioplayers/audioplayers.dart' as audio;
import 'package:vibration/vibration.dart';

class NotificationHelper {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static bool _isInitialized = false;
  static const String _channelId = 'danoggin_alerts';
  static const String _channelName = 'Danoggin Alerts';
  static const String _channelDescription = 'Alerts for check-in issues';

  static final Queue<String> _logMessages = Queue<String>();
  static const int _maxLogMessages = 100;

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

    print('Starting notification helper initialization...');

    // Initialize time zones
    tz_data.initializeTimeZones();

    // Basic Android settings
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // Enhanced iOS settings with explicit foreground delegation
    // Remove 'const' since we're using callbacks which are not const
    final DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      // Add this critical callback for iOS foreground notifications
      notificationCategories: [
        DarwinNotificationCategory(
          'danoggin_category',
          actions: [
            DarwinNotificationAction.plain(
              'view',
              'View',
              options: {DarwinNotificationActionOption.foreground},
            ),
          ],
        ),
      ],
      // Add onDidReceiveLocalNotification for older iOS versions
      onDidReceiveLocalNotification:
          (int id, String? title, String? body, String? payload) async {
        print('Received foreground notification: id=$id, title=$title');
        // Re-emit the notification to our stream to handle it in-app
        _notificationStreamController
            .add({'id': id, 'title': title, 'body': body, 'payload': payload});
      },
    );

    final InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        print('Notification clicked: ${response.id}');
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
          print('Notification channel created successfully');
        }
      } catch (e) {
        print('Error creating Android notification channel: $e');
        // Continue anyway - older versions may still work without explicit channel creation
      }
    }

    _isInitialized = true;
    print('Notifications initialized successfully');
  }

  /// Check if notifications are enabled
  static Future<bool> areNotificationsEnabled() async {
    if (!_isInitialized) {
      await initialize();
    }

    print('Checking notification permissions...');

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
          print('Android notification permission status: $enabled');
          return enabled;
        } catch (e) {
          print('Error calling areNotificationsEnabled: $e');
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

        print('iOS notification permission request result: $result');
        return result ?? false;
      }

      return false;
    } catch (e) {
      print('Error checking notification permissions: $e');
      return false;
    }
  }

  static Future<bool> showAlert({
    required int id,
    required String title,
    required String body,
    bool triggerRefresh = true,
  }) async {
    print('Attempting to show notification: id=$id, title=$title');

    if (!_isInitialized) {
      await initialize();
    }

    try {
      // Check if notifications are enabled
      final enabled = await areNotificationsEnabled();
      if (!enabled) {
        print('Notifications are not enabled for this app');
        return false;
      }

      // Enhanced Android notification details for better visibility
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

      // iOS notification details with available parameters only
      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'default',
        interruptionLevel: InterruptionLevel.active,
        // Only use parameters that are definitely available
        categoryIdentifier: 'danoggin_category',
      );

      const NotificationDetails platformDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      // Log more information about the notification
      print('Showing notification with following details:');
      print('  ID: $id');
      print('  Title: $title');
      print('  Body: $body');
      if (Platform.isAndroid) {
        print('  Platform: Android');
      } else if (Platform.isIOS) {
        print('  Platform: iOS');
      }

      await _notifications.show(
        id,
        title,
        body,
        platformDetails,
      );

      if (triggerRefresh) {
        _notificationStreamController
            .add({'id': id, 'title': title, 'body': body});
        print('Emitted notification event for refresh');
      }

      print('Alert notification sent successfully');
      return true;
    } catch (e) {
      print('Error showing notification: $e');
      return false;
    }
  }

  /// Test notifications to verify they work
  static Future<bool> testNotification() async {
    final id = DateTime.now().millisecond;
    final result = await showAlert(
      id: id,
      title: 'Danoggin Test',
      body:
          'This is a test notification. If you see this, notifications are working!',
    );

    print('Test notification result: $result');
    return result;
  }

  /// iOS-specific test notification method
  static Future<bool> testIOSNotification() async {
    try {
      if (!_isInitialized) {
        await initialize();
      }

      print('Testing iOS notification specifically...');

      // Request permissions explicitly before showing notification
      final iosPlugin = _notifications.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();

      final permGranted = await iosPlugin?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );

      print('iOS permissions request result: $permGranted');

      // Use only available parameters for iOS notification
      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        interruptionLevel: InterruptionLevel.active,
        categoryIdentifier: 'danoggin_category',
      );

      const NotificationDetails details = NotificationDetails(iOS: iosDetails);

      // Generate a unique ID
      final id = DateTime.now().millisecond;

      print('Sending iOS test notification with ID: $id');
      await _notifications.show(
        id,
        'iOS Test Notification',
        'This is a test notification specifically for iOS. It should appear even when the app is in the foreground.',
        details,
      );

      print('iOS test notification sent!');
      return true;
    } catch (e) {
      print('Error showing iOS notification: $e');
      return false;
    }
  }

  /// Cancel/remove a specific notification by ID
  static Future<void> cancelNotification(int id) async {
    try {
      await _notifications.cancel(id);
      print('Notification with ID $id canceled');
    } catch (e) {
      print('Error canceling notification: $e');
    }
  }

  /// Cancel all notifications
  static Future<void> cancelAllNotifications() async {
    try {
      await _notifications.cancelAll();
      print('All notifications canceled');
    } catch (e) {
      print('Error canceling all notifications: $e');
    }
  }

  /// Check Android SDK version
  static Future<int> _getAndroidSdkVersion() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      return androidInfo.version.sdkInt;
    } catch (e) {
      print('Error getting Android SDK version: $e');
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
      print('Android SDK version: $sdkVersion');
    }

    bool enabled = false;
    try {
      enabled = await areNotificationsEnabled();
    } catch (e) {
      print('Error checking notification permissions: $e');
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
        print(
            'Android notification permissions handled through channel creation');
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
          print('iOS notification permission request result: $result');
        }
      }
    } catch (e) {
      print('Error requesting notification permissions: $e');
    }
  }

  // Ensure background notifications are properly configured
  static Future<void> ensureBackgroundNotificationsEnabled() async {
    if (!_isInitialized) {
      await initialize();
    }

    // The notification channel created in initialize() should be sufficient
    // Just make sure permissions are properly requested
    await requestNotificationPermissions();

    print('Background notifications have been configured');
  }

  // Add cleanup method to dispose of the stream controller
  static void dispose() {
    _notificationStreamController.close();
  }

  static Future<bool> testDelayedNotification() async {
    try {
      if (!_isInitialized) {
        await initialize();
      }

      print('Testing delayed notification (3 seconds)...');

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

      // Generate a unique ID
      final id = DateTime.now().millisecond;

      // Schedule notification for 3 seconds later
      await _notifications.zonedSchedule(
        id,
        'Delayed Test Notification',
        'This notification was delayed by 3 seconds to simulate background behavior',
        tz.TZDateTime.now(tz.local).add(const Duration(seconds: 3)),
        details,
        androidAllowWhileIdle: true,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );

      print('Delayed notification scheduled!');
      return true;
    } catch (e) {
      print('Error scheduling delayed notification: $e');
      return false;
    }
  }

  static Future<bool> testForegroundNotificationiOS() async {
    clearLogs();
    log("Starting iOS foreground notification test");

    if (!_isInitialized) {
      log("Initializing notification system first");
      await initialize();
    }

    try {
      log("Testing basic foreground notification for iOS");

      // Force request permissions again
      if (Platform.isIOS) {
        log("Running on iOS platform - requesting permissions");
        final iosPlugin = _notifications.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();

        if (iosPlugin == null) {
          log("ERROR: Failed to get iOS plugin implementation");
          return false;
        }

        final permissionResult = await iosPlugin.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );

        log("Permission request result: $permissionResult");
      } else {
        log("Not running on iOS - skipping iOS-specific permission request");
      }

      // Try with absolute minimum configuration
      final id = DateTime.now().millisecond;
      log("Using notification ID: $id");

      if (Platform.isIOS) {
        log("Configuring iOS-specific notification parameters");

        // Show what version of iOS we're running on
        final deviceInfo = DeviceInfoPlugin();
        final iosInfo = await deviceInfo.iosInfo;
        log("iOS version: ${iosInfo.systemVersion}");

        // Using only essential iOS settings
        final details = NotificationDetails(
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
            interruptionLevel: InterruptionLevel.active,
          ),
        );

        log("Sending iOS notification with InterruptionLevel.active");
        await _notifications.show(
          id,
          'iOS Foreground Test',
          'Basic foreground notification test - ${DateTime.now().toString()}',
          details,
        );
        log("iOS notification show() method completed - notification sent");
      } else {
        log("Not running on iOS - using standard notification");
        await showAlert(
          id: id,
          title: 'Test Notification',
          body: 'Basic test notification',
          triggerRefresh: false,
        );
        log("Standard notification sent");
      }

      log("Test notification process completed successfully");
      return true;
    } catch (e, stackTrace) {
      log("ERROR in foreground notification test: $e");
      log("Stack trace: $stackTrace");
      return false;
    }
  }

// Add this method to NotificationHelper class
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

// Add this getter to access logs
  static List<String> get logs => List.from(_logMessages);

// Add a method to clear logs
  static void clearLogs() {
    _logMessages.clear();
  }

  static Future<bool> testProvisionalNotification() async {
    log("Starting iOS provisional notification test");

    if (!_isInitialized) {
      log("Initializing notification system first");
      await initialize();
    }

    try {
      if (Platform.isIOS) {
        // Request provisional authorization
        log("Requesting provisional authorization for iOS");

        final iosPlugin = _notifications.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();

        if (iosPlugin == null) {
          log("ERROR: Failed to get iOS plugin implementation");
          return false;
        }

        // Key difference: request provisional authorization
        final provisionalResult = await iosPlugin.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
          provisional: true, // This is the key difference
        );

        log("Provisional authorization result: $provisionalResult");

        // Try immediate notification with provisional authorization
        final id = DateTime.now().millisecond;

        const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          interruptionLevel: InterruptionLevel.active,
        );

        const NotificationDetails details =
            NotificationDetails(iOS: iosDetails);

        log("Sending iOS notification with provisional authorization");
        await _notifications.show(
          id,
          'iOS Provisional Test',
          'Testing notification with provisional authorization',
          details,
        );

        log("iOS provisional notification sent");
      } else {
        log("Not running on iOS - test not applicable");
      }

      return true;
    } catch (e) {
      log("ERROR in provisional notification test: $e");
      return false;
    }
  }

  static Future<void> showEnhancedInAppNotification(
      BuildContext context, String title, String body,
      {bool playSound = true, bool vibrate = true}) async {
    // Play notification sound
    if (playSound) {
      try {
        final player = audio.AudioPlayer();
        await player.play(audio.AssetSource('sounds/notification_sound.mp3'));
      } catch (e) {
        log("Error playing notification sound: $e");
      }
    }

    // Vibrate device
    if (vibrate) {
      try {
        if (await Vibration.hasVibrator() ?? false) {
          // Create a pattern similar to notification vibration
          Vibration.vibrate(pattern: [0, 250, 100, 250]);
        }
      } catch (e) {
        log("Error vibrating device: $e");
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
      // Fix for checking if the entry is still valid before removing
      try {
        // A simpler check to see if the context is still valid
        if (context.mounted) {
          entry.remove();
        }
      } catch (e) {
        log("Error removing notification overlay: $e");
        // Entry might have been removed already
      }
    });
  }

  static void trackAppState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _appInBackground = true;
    } else {
      _appInBackground = false;
    }
    log("App state changed to: $state, isBackground: $_appInBackground");
  }

// Advanced notification method that decides best approach based on app state
  static Future<void> showSmartNotification({
    required BuildContext? context,
    required int id,
    required String title,
    required String body,
  }) async {
    // If app is known to be in background, or if we don't have a context,
    // use system notification
    log("======== In showSmartNotification");
    if (_appInBackground || context == null) {
      log("App in background or no context - using system notification");
      await showAlert(
        id: id,
        title: title,
        body: body,
      );
      return;
    }

    // App is in foreground with context - use enhanced in-app notification
    log("App in foreground - using enhanced in-app notification");
    showEnhancedInAppNotification(context, title, body);
  }

  static void setCurrentContext(BuildContext context) {
    _currentContext = context;
  }
}
