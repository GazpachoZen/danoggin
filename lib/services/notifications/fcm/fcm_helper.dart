// lib/services/notifications/fcm/fcm_helper.dart
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../auth_service.dart';
import 'package:danoggin/utils/logger.dart';

/// Helper class for Firebase Cloud Messaging functionality
class FCMHelper {
  final Logger _logger = Logger();
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
      _logger.i('Firebase not initialized yet, cannot initialize FCM helper');
      return;
    }
    
    _messaging = FirebaseMessaging.instance;
    _logger.i('FCM helper initialized');
  }
  
  /// Initialize FCM permissions
  Future<void> requestPermissions() async {
    _logger.i('Requesting FCM permissions');
    
    try {
      // Check if Firebase is initialized
      if (Firebase.apps.isEmpty) {
        _logger.i('Firebase not initialized yet, skipping permission request');
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
        
        _logger.i('FCM permission status: ${settings.authorizationStatus}');
      } else {
        // Android automatically grants basic permission through manifest
        _logger.i('FCM permissions on Android granted by default');
      }
    } catch (e) {
      _logger.e('error requesting FCM permissions: $e');
    }
  }
  
  /// Get the FCM token for this device and save it to Firestore
  Future<String?> getAndSaveToken() async {
    try {
      // Check if Firebase is initialized
      if (Firebase.apps.isEmpty) {
        _logger.i('Firebase not initialized yet, cannot get FCM token');
        return null;
      }
      
      _messaging = FirebaseMessaging.instance;
      
      _logger.i('Getting FCM token');
      final token = await _messaging.getToken();
      
      if (token != null) {
        _logger.i('FCM token obtained: ${token.substring(0, 10)}...');
        
        // Save token to Firestore
        await _saveTokenToFirestore(token);
        return token;
      } else {
        _logger.i('Failed to obtain FCM token');
        return null;
      }
    } catch (e) {
      _logger.e('error getting FCM token: $e');
      return null;
    }
  }
  
  /// Save FCM token to Firestore with timestamp and proper error handling
  Future<void> _saveTokenToFirestore(String token) async {
    try {
      _logger.i('ATTEMPTING TO SAVE FCM TOKEN TO FIRESTORE');
      _logger.i('Token length: ${token.length}');
      _logger.i('Token preview: ${token.substring(0, 20)}...');
      
      // Check if user is authenticated
      final user = AuthService.currentUser;
      if (user == null) {
        _logger.e('error: No authenticated user - cannot save FCM token');
        return;
      }
      
      final uid = user.uid;
      _logger.i('Current user ID: $uid');
      
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
          _logger.i('New FCM token added to existing user document');
        } else {
          _logger.i('FCM token already exists, skipping duplicate save');
        }
      } else {
        // Create new user document with FCM token
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'fcmTokens': [tokenData],
          'fcmToken': token,
          'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        _logger.i('Created new user document with FCM token');
      }
      
      // Verification step
      final verifyDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final verifyData = verifyDoc.data();
      _logger.i('Verification: User document exists: ${verifyDoc.exists}');
      _logger.i('Verification: FCM token field exists: ${verifyData?.containsKey('fcmToken')}');
      _logger.i('Verification: FCM tokens array length: ${(verifyData?['fcmTokens'] as List?)?.length ?? 0}');
      
    } catch (e, stackTrace) {
      _logger.e('error saving FCM token to Firestore: $e');
      _logger.i('Stack trace: $stackTrace');
    }
  }
  
  /// Remove a token from Firestore
  Future<void> removeTokenFromFirestore(String token) async {
    try {
      final user = AuthService.currentUser;
      if (user == null) {
        _logger.i('No authenticated user - cannot remove FCM token');
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
      
      _logger.i('FCM token removed from Firestore');
    } catch (e) {
      _logger.e('error removing FCM token from Firestore: $e');
    }
  }
  
  /// Delete all FCM tokens for a user
  Future<void> clearAllTokens() async {
    try {
      final user = AuthService.currentUser;
      if (user == null) {
        _logger.i('No authenticated user - cannot clear FCM tokens');
        return;
      }
      
      final uid = user.uid;
      
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'fcmTokens': [],
        'fcmToken': null,
      });
      
      _logger.i('All FCM tokens cleared from Firestore');
    } catch (e) {
      _logger.e('error clearing FCM tokens from Firestore: $e');
    }
  }
  
  /// Get current notification settings status
  Future<AuthorizationStatus> getNotificationStatus() async {
    try {
      if (Firebase.apps.isEmpty) {
        _logger.i('Firebase not initialized, cannot get notification status');
        return AuthorizationStatus.notDetermined;
      }
      
      _messaging = FirebaseMessaging.instance;
      final settings = await _messaging.getNotificationSettings();
      return settings.authorizationStatus;
    } catch (e) {
      _logger.e('error getting notification status: $e');
      return AuthorizationStatus.notDetermined;
    }
  }
}