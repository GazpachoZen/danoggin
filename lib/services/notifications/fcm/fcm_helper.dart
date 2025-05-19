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
  
  /// Save FCM token to Firestore with timestamp and proper error handling
  Future<void> _saveTokenToFirestore(String token) async {
    try {
      _logger.log('ATTEMPTING TO SAVE FCM TOKEN TO FIRESTORE');
      _logger.log('Token length: ${token.length}');
      _logger.log('Token preview: ${token.substring(0, 20)}...');
      
      // Check if user is authenticated
      final user = AuthService.currentUser;
      if (user == null) {
        _logger.log('ERROR: No authenticated user - cannot save FCM token');
        return;
      }
      
      final uid = user.uid;
      _logger.log('Current user ID: $uid');
      
      // Create token object with regular timestamp (not FieldValue.serverTimestamp())
      final tokenData = {
        'token': token,
        'createdAt': DateTime.now().toIso8601String(), // Use regular timestamp for arrays
        'platform': Platform.isIOS ? 'ios' : 'android',
      };
      
      // Get existing user document to check for existing tokens
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      
      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;
        final existingTokens = userData['fcmTokens'] as List<dynamic>? ?? [];
        
        // Check if this exact token already exists
        bool tokenExists = existingTokens.any((tokenDoc) => 
          tokenDoc is Map<String, dynamic> && tokenDoc['token'] == token);
        
        if (!tokenExists) {
          // Add new token and update convenience field
          await FirebaseFirestore.instance.collection('users').doc(uid).update({
            'fcmTokens': FieldValue.arrayUnion([tokenData]),
            'fcmToken': token, // Convenience field for latest token
            'fcmTokenUpdatedAt': FieldValue.serverTimestamp(), // This is OK outside arrays
          });
          _logger.log('New FCM token added to existing user document');
        } else {
          _logger.log('FCM token already exists, skipping duplicate save');
        }
      } else {
        // Create new user document with FCM token
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'fcmTokens': [tokenData],
          'fcmToken': token,
          'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        _logger.log('Created new user document with FCM token');
      }
      
      // Verification step
      final verifyDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final verifyData = verifyDoc.data();
      _logger.log('Verification: User document exists: ${verifyDoc.exists}');
      _logger.log('Verification: FCM token field exists: ${verifyData?.containsKey('fcmToken')}');
      _logger.log('Verification: FCM tokens array length: ${(verifyData?['fcmTokens'] as List?)?.length ?? 0}');
      
    } catch (e, stackTrace) {
      _logger.log('ERROR saving FCM token to Firestore: $e');
      _logger.log('Stack trace: $stackTrace');
    }
  }
  
  /// Remove a token from Firestore
  Future<void> removeTokenFromFirestore(String token) async {
    try {
      final user = AuthService.currentUser;
      if (user == null) {
        _logger.log('No authenticated user - cannot remove FCM token');
        return;
      }
      
      final uid = user.uid;
      
      // Get current tokens
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (!userDoc.exists) return;
      
      final userData = userDoc.data() as Map<String, dynamic>;
      final existingTokens = userData['fcmTokens'] as List<dynamic>? ?? [];
      
      // Find and remove the token object that matches
      final updatedTokens = existingTokens.where((tokenDoc) {
        if (tokenDoc is Map<String, dynamic>) {
          return tokenDoc['token'] != token;
        }
        return true;
      }).toList();
      
      // Update the document
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'fcmTokens': updatedTokens,
      });
      
      _logger.log('FCM token removed from Firestore');
    } catch (e) {
      _logger.log('Error removing FCM token from Firestore: $e');
    }
  }
  
  /// Delete all FCM tokens for a user
  Future<void> clearAllTokens() async {
    try {
      final user = AuthService.currentUser;
      if (user == null) {
        _logger.log('No authenticated user - cannot clear FCM tokens');
        return;
      }
      
      final uid = user.uid;
      
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
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