import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:danoggin/services/auth_service.dart';
import 'package:danoggin/services/notifications/notification_manager.dart';
import 'package:danoggin/repositories/responder_settings_repository.dart';
import 'package:danoggin/controllers/inactvity_monitor.dart';
import 'package:danoggin/utils/logger.dart';

class ObserverController {
  // State variables
  String? lastAcknowledgedId;
  String? lastNotifiedId;
  String? lastInactivityAlertId;
  String? selectedResponderUid;
  Map<String, String> responderMap = {};
  int inactivityThresholdHours = 24; // Default value

  // Listeners for Firestore
  Map<String, StreamSubscription<QuerySnapshot>> _checkInSubscriptions = {};

  // Timer for checking inactivity (kept separate)
  Timer? dataRefreshTimer;

  // Callback to notify parent of state changes
  final VoidCallback onStateChanged;

  // Constructor
  ObserverController({required this.onStateChanged});

  // Cleanup
  void dispose() {
    dataRefreshTimer?.cancel();

    // Cancel all existing subscriptions
    _checkInSubscriptions.forEach((key, subscription) {
      subscription.cancel();
    });
    _checkInSubscriptions.clear();
  }

// Initialize and load data
  Future<void> initialize() async {
    await loadLastAcknowledged();
    await loadResponders();
    await loadInactivityThreshold();
    startDataRefreshTimer();
  }

  // Load inactivity threshold from Firestore
  Future<void> loadInactivityThreshold() async {
    try {
      final uid = AuthService.currentUserId;
      final threshold =
          await ResponderSettingsRepository.getInactivityThreshold(uid);
      inactivityThresholdHours = threshold;
      onStateChanged();
    } catch (e) {
      Logger().e('Error loading inactivity threshold: $e');
    }
  }

  // Load the last acknowledged check-in ID
  Future<void> loadLastAcknowledged() async {
    final prefs = await SharedPreferences.getInstance();
    lastAcknowledgedId = prefs.getString('lastAcknowledgedCheckInId');
    onStateChanged();
  }

  // Load all responders associated with this observer
  Future<void> loadResponders() async {
    try {
      final observerUid = AuthService.currentUserId;
      final observerDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(observerUid)
          .get();

      final userData = observerDoc.data();
      final observingMap =
          userData?['observing'] as Map<String, dynamic>? ?? {};

      responderMap = Map<String, String>.from(observingMap);

      // Auto-select a responder if needed
      if (selectedResponderUid == null && responderMap.isNotEmpty) {
        selectedResponderUid = responderMap.keys.first;
      } else if (responderMap.isEmpty) {
        selectedResponderUid = null;
      } else if (selectedResponderUid != null &&
          !responderMap.containsKey(selectedResponderUid)) {
        selectedResponderUid = responderMap.keys.first;
      }

      // Setup listeners for all responders
      _setupCheckInListeners();

      onStateChanged();
    } catch (e) {
      Logger().e('Error loading responders: $e');
    }
  }

  // Select a responder to monitor
  void selectResponder(String responderUid) {
    selectedResponderUid = responderUid;
    onStateChanged();
  }

  // Start the timer to check for inactivity periodically
  void startDataRefreshTimer() {
    // Refresh every 5 minutes to check for inactivity
    const refreshDuration = Duration(minutes: 5);
    dataRefreshTimer?.cancel();
    dataRefreshTimer = Timer.periodic(refreshDuration, (_) {
      loadResponders();
      checkInactivity();
    });
  }

  // Setup real-time listeners for check-ins
  void _setupCheckInListeners() {
    // Cancel any existing subscriptions
    _checkInSubscriptions.forEach((key, subscription) {
      subscription.cancel();
    });
    _checkInSubscriptions.clear();

    // Setup a listener for each responder
    for (final responderUid in responderMap.keys) {
      final responderName = responderMap[responderUid] ?? 'Unknown';

      final subscription = FirebaseFirestore.instance
          .collection('responder_status')
          .doc(responderUid)
          .collection('check_ins')
          .orderBy('timestamp', descending: true)
          .limit(1)
          .snapshots()
          .listen((snapshot) {
        if (snapshot.docs.isEmpty) return;

        final doc = snapshot.docs.first;
        final data = doc.data();
        final result = data['result'] as String;
        final timestamp = DateTime.tryParse(data['timestamp'] as String);

        // Skip if we can't parse the timestamp
        if (timestamp == null) return;

        final now = DateTime.now();
        final checkInAge = now.difference(timestamp);

        Logger().i(
            'Real-time update: responder=$responderName, result=$result, age=${checkInAge.inMinutes}m');

        // Create a unique identifier for this check-in
      }, onError: (error) {
        Logger().e('Error in check-in listener for $responderName: $error');
      });

      // Store the subscription for later cleanup
      _checkInSubscriptions[responderUid] = subscription;
    }
  }

  // Acknowledge a check-in issue
  Future<void> acknowledge(String compositeKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lastAcknowledgedCheckInId', compositeKey);
    lastAcknowledgedId = compositeKey;
    onStateChanged();
  }

  // Check inactivity for all responders
  Future<void> checkInactivity() async {
    try {
      // Check each linked responder for inactivity
      for (final responderUid in responderMap.keys) {
        final responderName = responderMap[responderUid] ?? 'Unknown';

        // Get the responder's active hours from Firestore
        final activeHours =
            await ResponderSettingsRepository.getActiveHours(responderUid);

        // Perform inactivity check
        await InactivityMonitor.checkResponderInactivity(
          responderUid: responderUid,
          responderName: responderName,
          activeHours: activeHours,
          inactivityThresholdHours: inactivityThresholdHours,
          lastInactivityAlertKey: lastInactivityAlertId,
          onAlertSent: (alertKey) {
            lastInactivityAlertId = alertKey;
            onStateChanged();
          },
        );
      }
    } catch (e) {
      Logger().e("Error in checkInactivity: $e");
    }
  }

// Test notifications functionality
  Future<void> testNotifications(BuildContext context) async {
    try {
      // Set the current context for smart notifications
      NotificationManager().setCurrentContext(context);

      // Use platform-aware notification test method
      await NotificationManager().useBestNotification(
        id: DateTime.now().millisecondsSinceEpoch,
        title: 'Danoggin Test Notification',
        body:
            'This is a test notification. If you see this, notifications are working!',
        triggerRefresh: false,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Test notification sent!'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      Logger().e('Error testing notifications: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error sending test notification: $e'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }
}
