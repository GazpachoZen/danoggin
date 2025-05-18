// lib/services/notifications/fcm/fcm_notification_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import '../base/notification_service.dart';
import '../base/notification_handler.dart';
import '../base/notification_logger.dart';
import '../notification_manager.dart';
import 'fcm_helper.dart';

/// FCM implementation of the notification service interface
class FCMNotificationService implements NotificationService {
  // Singleton instance
  static final FCMNotificationService _instance = FCMNotificationService._internal();
  factory FCMNotificationService() => _instance;
  
  // Logger and FCM helper
  final NotificationLogger _logger = NotificationLogger();
  late FCMHelper _fcmHelper;
  
  // Notification handler for event stream
  final NotificationHandler _handler = DefaultNotificationHandler();
  
  // FCM instance
  late FirebaseMessaging _messaging;
  
  // Initialization flag
  bool _isInitialized = false;
  
  // Current UI context
  BuildContext? _currentContext;
  
  // App state tracking
  bool _appInBackground = false;
  
FCMNotificationService._internal() {
  _fcmHelper = FCMHelper();
}
  
  @override
@override
Future<void> initialize() async {
  if (_isInitialized) return;
  
  _logger.log('Initializing FCM notification service');
  
  try {
    // Check if Firebase is initialized before accessing
    if (Firebase.apps.isNotEmpty) {
      _messaging = FirebaseMessaging.instance;
      
      // Set up message handlers
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);
      
      // Check for initial message
      final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
      if (initialMessage != null) {
        _handleInitialMessage(initialMessage);
      }
      
      // Request permissions and get token
      await _fcmHelper.requestPermissions();
      await _fcmHelper.getAndSaveToken();
      
      // Set up token refresh listener
      FirebaseMessaging.instance.onTokenRefresh.listen((token) {
        _fcmHelper.getAndSaveToken();
      });
      
      _isInitialized = true;
      _logger.log('FCM notification service initialized successfully');
    } else {
      _logger.log('Firebase not initialized yet, FCM initialization skipped');
    }
  } catch (e) {
    _logger.log('Error initializing FCM notification service: $e');
  }
}

  @override
  Future<bool> areNotificationsEnabled() async {
    if (!_isInitialized) {
      await initialize();
    }
    
    try {
      final settings = await _messaging.getNotificationSettings();
      final enabled = settings.authorizationStatus == AuthorizationStatus.authorized;
      _logger.log('FCM notifications enabled: $enabled');
      return enabled;
    } catch (e) {
      _logger.log('Error checking FCM notification permissions: $e');
      return false;
    }
  }

  @override
  Future<void> requestPermissions() async {
    await _fcmHelper.requestPermissions();
  }

  // Handle messages received while app is in foreground
// Handle messages received while app is in foreground
void _handleForegroundMessage(RemoteMessage message) {
  _logger.log('Handling foreground FCM message: ${message.messageId}');
  
  try {
    final notification = message.notification;
    final data = message.data;
    
    if (notification != null) {
      // Show the notification as a system notification even in foreground
      // We'll use the local notification service for this
      _showForegroundNotification(
        title: notification.title ?? 'Danoggin',
        body: notification.body ?? '',
        messageId: message.messageId ?? '',
      );
    }
    
    // Convert the message to an event
    final Map<String, dynamic> eventData = {
      'messageId': message.messageId,
      'title': notification?.title,
      'body': notification?.body,
      'data': data,
    };
    
    // Add to event stream
    _handler.addNotificationEvent(eventData);
    
    _logger.log('FCM foreground message processed');
  } catch (e) {
    _logger.log('Error handling FCM foreground message: $e');
  }
}

// Helper method to show foreground notifications as system notifications
Future<void> _showForegroundNotification({
  required String title,
  required String body,
  required String messageId,
}) async {
  try {
    // Use the local notification service to show the notification
    // This will ensure it appears even when the app is in foreground
    await NotificationManager().useBestNotification(
      id: messageId.hashCode,
      title: title,
      body: body,
      triggerRefresh: false,
    );
    
    _logger.log('Foreground notification displayed: $title');
  } catch (e) {
    _logger.log('Error showing foreground notification: $e');
  }
}  
  // Handle when app is opened from notification in background/terminated state
  void _handleMessageOpenedApp(RemoteMessage message) {
    _logger.log('App opened from FCM notification: ${message.messageId}');
    
    try {
      final notification = message.notification;
      final data = message.data;
      
      // Convert the message to an event
      final Map<String, dynamic> eventData = {
        'messageId': message.messageId,
        'title': notification?.title,
        'body': notification?.body,
        'data': data,
        'openedApp': true,
      };
      
      // Add to event stream
      _handler.addNotificationEvent(eventData);
    } catch (e) {
      _logger.log('Error handling opened app FCM message: $e');
    }
  }
  
  // Handle initial message (app opened from terminated state)
  void _handleInitialMessage(RemoteMessage message) {
    _logger.log('App opened from terminated state via FCM: ${message.messageId}');
    
    try {
      final notification = message.notification;
      final data = message.data;
      
      // Convert the message to an event
      final Map<String, dynamic> eventData = {
        'messageId': message.messageId,
        'title': notification?.title,
        'body': notification?.body,
        'data': data,
        'initialMessage': true,
      };
      
      // Add to event stream
      _handler.addNotificationEvent(eventData);
    } catch (e) {
      _logger.log('Error handling initial FCM message: $e');
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
    // FCM can't directly show notifications from the client
    // This is just a placeholder that returns false to indicate
    // it couldn't show a notification (which is expected behavior)
    _logger.log('FCM cannot show notifications directly from client');
    return false;
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
    // FCM can't directly schedule notifications from the client
    _logger.log('FCM cannot schedule notifications directly from client');
    return false;
  }

  @override
  Future<void> showInAppNotification({
    required BuildContext context,
    required String title,
    required String body,
    bool playSound = true,
  }) async {
    // FCM doesn't handle in-app notifications directly
    _logger.log('FCM service does not handle in-app notifications');
  }

  @override
  Future<void> cancelNotification(int id) async {
    // FCM doesn't support cancelling notifications directly
    _logger.log('Cancelling FCM notifications not supported');
  }

  @override
  Future<void> cancelAllNotifications() async {
    // FCM doesn't support cancelling notifications directly
    _logger.log('Cancelling all FCM notifications not supported');
  }

  @override
  void trackAppState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || 
        state == AppLifecycleState.detached) {
      _appInBackground = true;
    } else if (state == AppLifecycleState.resumed) {
      _appInBackground = false;
    }
    _logger.log('FCM tracked app state change to: $state');
  }

  @override
  void setCurrentContext(BuildContext? context) {
    _currentContext = context;
  }

  @override
  void dispose() {
    _handler.dispose();
  }
  
  // Get notification event stream
  Stream<dynamic> get notificationEvents => _handler.notificationEvents;
  
  // Get FCM helper for direct access to token functions
  FCMHelper get fcmHelper => _fcmHelper;
}