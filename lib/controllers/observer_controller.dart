import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:danoggin/services/auth_service.dart';
import 'package:danoggin/services/notification_helper.dart';
import 'package:danoggin/repositories/responder_settings_repository.dart';
import 'package:danoggin/controllers/inactvity_monitor.dart';

class ObserverController {
  // State variables
  String? lastAcknowledgedId;
  String? lastNotifiedId;
  String? lastInactivityAlertId;
  String? selectedResponderUid;
  Map<String, String> responderMap = {};
  int inactivityThresholdHours = 24; // Default value

  // Timer for background operations
  Timer? pollingTimer;
  Timer? dataRefreshTimer;
  
  // Callback to notify parent of state changes
  final VoidCallback onStateChanged;
  
  // Constructor
  ObserverController({required this.onStateChanged});
  
  // Cleanup
  void dispose() {
    pollingTimer?.cancel();
    dataRefreshTimer?.cancel();
  }
  
// Initialize and load data
  Future<void> initialize() async {
    await loadLastAcknowledged();
    await loadResponders();
    await loadInactivityThreshold();
    startPollingLoop();
    startDataRefreshTimer();
  }
  
  // Load inactivity threshold from Firestore
  Future<void> loadInactivityThreshold() async {
    try {
      final uid = AuthService.currentUserId;
      final threshold = await ResponderSettingsRepository.getInactivityThreshold(uid);
      inactivityThresholdHours = threshold;
      onStateChanged();
    } catch (e) {
      print('Error loading inactivity threshold: $e');
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
      
      onStateChanged();
    } catch (e) {
      print('Error loading responders: $e');
    }
  }

  // Select a responder to monitor
  void selectResponder(String responderUid) {
    selectedResponderUid = responderUid;
    onStateChanged();
  }

  // Start the timer to refresh data periodically
  void startDataRefreshTimer() {
    // Refresh every 1 minute
    const refreshDuration = Duration(minutes: 1);
    dataRefreshTimer?.cancel();
    dataRefreshTimer = Timer.periodic(refreshDuration, (_) {
      loadResponders();
    });
  }

  // Start the polling loop to check responder status
  Future<void> startPollingLoop() async {
    final prefs = await SharedPreferences.getInstance();
    final interval = prefs.getDouble('observerPollInterval') ?? 2;
    final duration = Duration(minutes: interval.round());

    pollingTimer?.cancel();
    print("Starting polling loop with duration=$duration");
    pollingTimer = Timer.periodic(duration, (_) => checkResponderStatus());
  }

  // Acknowledge a check-in issue
  Future<void> acknowledge(String compositeKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lastAcknowledgedCheckInId', compositeKey);
    lastAcknowledgedId = compositeKey;
    onStateChanged();
  }

  // Check the status of all responders
// Check the status of all responders
  Future<void> checkResponderStatus() async {
    try {
      // Get the responder UIDs that this observer is linked to
      final observerUid = AuthService.currentUserId;
      final observerDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(observerUid)
          .get();

      final userData = observerDoc.data();
      final observingMap =
          userData?['observing'] as Map<String, dynamic>? ?? {};
      final responderUids = observingMap.keys.toList();

      if (responderUids.isEmpty) {
        print("No linked responders found");
        return;
      }

      // Track notifications sent in this polling cycle to avoid duplicates
      List<String> notifiedInThisCycle = [];

      // Check each linked responder
      for (final responderUid in responderUids) {
        final responderName = observingMap[responderUid];

        // Use get() to force a fresh read from Firestore
        final snapshot = await FirebaseFirestore.instance
            .collection('responder_status')
            .doc(responderUid)
            .collection('check_ins')
            .orderBy('timestamp', descending: true)
            .limit(1)
            .get();

        final now = DateTime.now();
        print(
            "Checking responder $responderName ($responderUid) @ ${now.hour}:${now.minute}:${now.second}");

        if (snapshot.docs.isEmpty) {
          // Handle case where no check-ins exist yet
          print("No check-ins found for responder: $responderName");
          continue;
        }

        final doc = snapshot.docs.first;
        final data = doc.data();
        final result = data['result'] as String;
        final timestamp = DateTime.tryParse(data['timestamp'] as String);
        final docId = doc.id;

        // Skip if we can't parse the timestamp
        if (timestamp == null) continue;

        final checkInAge = now.difference(timestamp);
        final mostRecentTimeStr =
            DateFormat('M/d h:mma').format(timestamp).toLowerCase();

        print(
            "Found check-in: id=$docId, result=$result, age=${checkInAge.inMinutes}m");

        // Create a unique identifier for this check-in
        final checkInKey = "$responderUid:$docId";

        // Only notify for recent check-ins that are missed or incorrect
        if ((result == 'missed' || result == 'incorrect') &&
            checkInAge.inHours < 24) {
          // Only consider relatively recent check-ins (last 24h)

          // Check if we've already acknowledged this issue
          final isAcknowledged = checkInKey == lastAcknowledgedId;

          // Check if we've already notified about this issue in this polling cycle
          final alreadyNotifiedThisCycle =
              notifiedInThisCycle.contains(checkInKey);

          if (!isAcknowledged && !alreadyNotifiedThisCycle) {
            print("Issue detected: $responderName had a $result check-in");

            // Mark this as notified in this cycle to avoid duplicate notifications
            notifiedInThisCycle.add(checkInKey);

            // Update tracking of last notification
            lastNotifiedId = checkInKey;
            onStateChanged();

            // Save to persistent storage
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('lastNotifiedId', checkInKey);

            // Show notification
            await NotificationHelper.showAlert(
              id: responderUid.hashCode.abs(),
              title: 'Danoggin Alert',
              body:
                  '$responderName had a $result check-in at $mostRecentTimeStr',
            );

            print("Notification sent for $responderName's $result check-in");
          }
        }
        
        // Check for inactivity (regardless of check-in result)
        // Get the responder's active hours from Firestore
        final activeHours = await ResponderSettingsRepository.getActiveHours(responderUid);
        
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
      print("Error in checkResponderStatus: $e");
    }
  }

  // Test notifications functionality
  Future<void> testNotifications(BuildContext context) async {
    try {
      // Try to check if notifications are enabled
      bool enabled = true;
      try {
        enabled = await NotificationHelper.areNotificationsEnabled();
      } catch (e) {
        print('Error checking notification permissions: $e');
        // If we can't check, assume they're enabled
      }

      if (!enabled) {
        // Show manual instructions if notifications are disabled
        NotificationHelper.openNotificationSettings(context);
        return;
      }

      // Test notification
      await NotificationHelper.testNotification();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Test notification sent!'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      print('Error testing notifications: $e');
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