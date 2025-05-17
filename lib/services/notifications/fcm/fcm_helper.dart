// lib/services/notifications/fcm/fcm_helper.dart
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../base/notification_logger.dart';
import '../../auth_service.dart';

/// Helper class for Firebase Cloud Messaging functionality
class FCMHelper {
  final NotificationLogger _logger = NotificationLogger();
  late FirebaseMessaging _messaging;
  
  FCMHelper() {
    // Initialize only if Firebase is ready
    if (Firebase.apps.isNotEmpty) {
      _messaging = FirebaseMessaging.instance;
    }
  }
  
  /// Initialize FCM helper
  Future<void> initialize() async {
    if (Firebase.apps.isEmpty) {
      _logger.log('Firebase not initialized yet, cannot initialize FCM helper');
      return;
    }
    
    _messaging = FirebaseMessaging.instance;
    _logger.log('FCM helper initialized');
  }
  
  /// Initialize FCM permissions
  Future<void> requestPermissions() async {
    _logger.log('Requesting FCM permissions');
    
    try {
      // Check if Firebase is initialized
      if (Firebase.apps.isEmpty) {
        _logger.log('Firebase not initialized yet, skipping permission request');
        return;
      }
      
      _messaging = FirebaseMessaging.instance;
      
      if (Platform.isIOS) {
        // iOS needs explicit permission request
        final settings = await _messaging.requestPermission(
          alert: true,
          announcement: false,
          badge: true,
          carPlay: false,
          criticalAlert: false,
          provisional: false,
          sound: true,
        );
        
        _logger.log('FCM permission status: ${settings.authorizationStatus}');
      } else {
        // Android automatically grants basic permission through manifest
        _logger.log('FCM permissions on Android granted by default');
      }
    } catch (e) {
      _logger.log('Error requesting FCM permissions: $e');
    }
  }
  
  /// Get the FCM token for this device and save it to Firestore
  Future<String?> getAndSaveToken() async {
    try {
      // Check if Firebase is initialized
      if (Firebase.apps.isEmpty) {
        _logger.log('Firebase not initialized yet, cannot get FCM token');
        return null;
      }
      
      _messaging = FirebaseMessaging.instance;
      
      _logger.log('Getting FCM token');
      final token = await _messaging.getToken();
      
      if (token != null) {
        _logger.log('FCM token obtained: ${token.substring(0, 10)}...');
        
        // Save token to Firestore
        await _saveTokenToFirestore(token);
        return token;
      } else {
        _logger.log('Failed to obtain FCM token');
        return null;
      }
    } catch (e) {
      _logger.log('Error getting FCM token: $e');
      return null;
    }
  }
  
  /// Save FCM token to Firestore for server-side targeting
  Future<void> _saveTokenToFirestore(String token) async {
    try {
      final user = AuthService.currentUserId;
      
      // Save to users collection
      await FirebaseFirestore.instance.collection('users').doc(user).update({
        'fcmTokens': FieldValue.arrayUnion([token]),
        'fcmToken': token, // Also save as single field for compatibility
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      });
      
      _logger.log('FCM token saved to Firestore');
    } catch (e) {
      _logger.log('Error saving FCM token to Firestore: $e');
      
      // Try to create the document if it doesn't exist
      try {
        final user = AuthService.currentUserId;
        
        // If update failed, try to set the document instead
        await FirebaseFirestore.instance.collection('users').doc(user).set({
          'fcmTokens': [token],
          'fcmToken': token,
          'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        
        _logger.log('FCM token saved to Firestore with merge');
      } catch (e2) {
        _logger.log('Error saving FCM token to Firestore (second attempt): $e2');
      }
    }
  }
  
  /// Remove a token from Firestore
  Future<void> removeTokenFromFirestore(String token) async {
    try {
      final user = AuthService.currentUserId;
      
      await FirebaseFirestore.instance.collection('users').doc(user).update({
        'fcmTokens': FieldValue.arrayRemove([token]),
      });
      
      _logger.log('FCM token removed from Firestore');
    } catch (e) {
      _logger.log('Error removing FCM token from Firestore: $e');
    }
  }
  
  /// Delete all FCM tokens for a user
  Future<void> clearAllTokens() async {
    try {
      final user = AuthService.currentUserId;
      
      await FirebaseFirestore.instance.collection('users').doc(user).update({
        'fcmTokens': [],
        'fcmToken': null,
      });
      
      _logger.log('All FCM tokens cleared from Firestore');
    } catch (e) {
      _logger.log('Error clearing FCM tokens from Firestore: $e');
    }
  }
  
  /// Get current notification settings status
  Future<AuthorizationStatus> getNotificationStatus() async {
    try {
      if (Firebase.apps.isEmpty) {
        _logger.log('Firebase not initialized, cannot get notification status');
        return AuthorizationStatus.notDetermined;
      }
      
      _messaging = FirebaseMessaging.instance;
      final settings = await _messaging.getNotificationSettings();
      return settings.authorizationStatus;
    } catch (e) {
      _logger.log('Error getting notification status: $e');
      return AuthorizationStatus.notDetermined;
    }
  }
}