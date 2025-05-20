import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:danoggin/services/notifications/notification_manager.dart';
import 'package:danoggin/utils/timezone_helper.dart';
import 'package:danoggin/utils/logger.dart';

// Development mode flag - set to false for production
const bool kDevModeEnabled = true;
// Ultra-fast testing uses minutes instead of hours (only active if kDevModeEnabled is true)
const bool kUltraFastTesting = false;

class InactivityMonitor {
  // Default inactivity threshold in hours
  static const int defaultInactivityThresholdHours = 24;

  // Check for responder inactivity
  static Future<void> checkResponderInactivity({
    required String responderUid,
    required String responderName,
    required Map<String, dynamic>? activeHours,
    required int inactivityThresholdHours,
    required String? lastInactivityAlertKey,
    required Function(String) onAlertSent,
  }) async {
    try {
      // Skip check if active hours are not available
      if (activeHours == null) {
        Logger().i('No active hours available for responder: $responderName');
        return;
      }

      // Extract start and end hours
      final startHourStr = activeHours['startHour'] as String?;
      final endHourStr = activeHours['endHour'] as String?;
      final responderTimeZone = activeHours['timeZone'] as String?;

      if (startHourStr == null || endHourStr == null) {
        Logger().i('Invalid active hours for responder: $responderName');
        return;
      }

      // Get observer's current time zone
      final observerTimeZone = TimezoneHelper.getCurrentTimeZone();

      // Parse active hours
      final startHourParts = startHourStr.split(':').map(int.parse).toList();
      final endHourParts = endHourStr.split(':').map(int.parse).toList();
      final startTime =
          TimeOfDay(hour: startHourParts[0], minute: startHourParts[1]);
      final endTime = TimeOfDay(hour: endHourParts[0], minute: endHourParts[1]);

      // Get current time in observer's time zone
      final now = DateTime.now();
      final currentTime = TimeOfDay.fromDateTime(now);

      // Convert responder's active hours to observer's time zone for comparison
      TimeOfDay convertedStartTime = startTime;
      TimeOfDay convertedEndTime = endTime;

      if (responderTimeZone != null && responderTimeZone != observerTimeZone) {
        Logger().i(
            'Converting from responder time zone ($responderTimeZone) to observer time zone ($observerTimeZone)');

        try {
          // Initialize timezone helper
          await TimezoneHelper.initialize();

          convertedStartTime = TimezoneHelper.convertTimeOfDay(
              startTime, responderTimeZone, observerTimeZone);

          convertedEndTime = TimezoneHelper.convertTimeOfDay(
              endTime, responderTimeZone, observerTimeZone);

          Logger().i('Converted active hours: $startTime -> $convertedStartTime');
          Logger().i('Converted active hours: $endTime -> $convertedEndTime');
        } catch (e) {
          Logger().e('Error converting time zones: $e');
          // Continue with original times if conversion fails
        }
      }

      // Check if current time is within active hours
      if (!TimezoneHelper.isWithinActiveHours(
          currentTime, convertedStartTime, convertedEndTime)) {
        Logger().i(
            'Current time is outside active hours for responder: $responderName');
        Logger().i('Current: ${currentTime.hour}:${currentTime.minute}, ' +
            'Active hours: ${convertedStartTime.hour}:${convertedStartTime.minute} - ' +
            '${convertedEndTime.hour}:${convertedEndTime.minute}');
        return;
      }

      // Get the most recent check-in
      final snapshot = await FirebaseFirestore.instance
          .collection('responder_status')
          .doc(responderUid)
          .collection('check_ins')
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();

      // If no check-ins found, this might be a new user
      if (snapshot.docs.isEmpty) {
        Logger().i('No check-ins found for responder: $responderName');
        return;
      }

      // Get the most recent check-in details
      final latestDoc = snapshot.docs.first;
      final latestData = latestDoc.data();
      final timestampStr = latestData['timestamp'] as String?;

      if (timestampStr == null) {
        Logger().i(
            'Invalid timestamp for latest check-in of responder: $responderName');
        return;
      }

      final timestamp = DateTime.tryParse(timestampStr);
      if (timestamp == null) {
        Logger().i(
            'Failed to parse timestamp for latest check-in of responder: $responderName');
        return;
      }

      // Calculate time since last activity
      final timeSinceLastActivity = now.difference(timestamp);

      // In dev mode, print detailed inactivity time info
      if (kDevModeEnabled) {
        Logger().i(
            'DEV MODE: $responderName\'s last activity was ${timeSinceLastActivity.inHours} hours and ' +
                '${timeSinceLastActivity.inMinutes % 60} minutes ago');
        Logger().i('DEV MODE: Threshold set to $inactivityThresholdHours hours');
      }

      // Check if inactive for longer than threshold
      bool isInactive = false;
      if (kDevModeEnabled && kUltraFastTesting) {
        // In ultra-fast mode, compare minutes instead of hours
        isInactive =
            timeSinceLastActivity.inMinutes >= inactivityThresholdHours;
        if (isInactive) {
          Logger().i(
              'DEV MODE ULTRA-FAST: Using minutes (${timeSinceLastActivity.inMinutes}) instead of hours for testing!');
        }
      } else {
        // Normal mode - compare hours
        isInactive = timeSinceLastActivity.inHours >= inactivityThresholdHours;
      }

      if (isInactive) {
        // Generate a unique alert key
        final alertKey =
            '$responderUid:inactivity:${now.millisecondsSinceEpoch}';

        // Check if we've already sent an alert for this inactivity period
        if (alertKey == lastInactivityAlertKey) {
          Logger().i('Already sent inactivity alert for responder: $responderName');
          return;
        }

        // Format the time of last activity in the observer's local time
        final lastActivityTime =
            DateFormat('M/d h:mma').format(timestamp).toLowerCase();

        // Calculate how many hours of inactivity
        final inactiveHours = kDevModeEnabled && kUltraFastTesting
            ? timeSinceLastActivity.inMinutes
            : timeSinceLastActivity.inHours;

        // Include time zone information in the notification
        String timeZoneInfo = '';
        if (responderTimeZone != null &&
            responderTimeZone != observerTimeZone) {
          timeZoneInfo = ' ($responderTimeZone)';
        }

        // Add dev mode indicator in notification if enabled
        String devModePrefix = '';
        if (kDevModeEnabled) {
          devModePrefix = kUltraFastTesting ? '[DEV-ULTRA] ' : '[DEV] ';
        }

        // Format the notification message
        final inactivityPeriod = kDevModeEnabled && kUltraFastTesting
            ? '$inactiveHours minutes'
            : '$inactiveHours hours';

        // Send notification
        await NotificationManager().useBestNotification(
          id: 'inactivity-${responderUid.hashCode}'.hashCode,
          title: '${devModePrefix}Danoggin Inactivity Alert',
          body: '$responderName has been inactive for $inactivityPeriod. ' +
              'Last active at $lastActivityTime$timeZoneInfo.',
          triggerRefresh: true,
        );

        Logger().i('Inactivity alert sent for responder: $responderName');

        // Update tracking
        onAlertSent(alertKey);
      } else {
        Logger().i(
            'Responder $responderName is active within threshold (${timeSinceLastActivity.inHours} hours)');
      }
    } catch (e) {
      Logger().e('Error checking inactivity for responder $responderName: $e');
    }
  }

  // Add this method to ensure inactivity alert is properly formatted
  static Future<void> sendInactivityAlert({
    required String responderUid,
    required String responderName,
    required int inactiveHours,
    required String lastActivityTime,
    required String? timeZoneInfo,
    required Function(String) onAlertSent,
    required String alertKey,
  }) async {
    try {
      // Add dev mode indicator in notification if enabled
      String devModePrefix = '';
      if (kDevModeEnabled) {
        devModePrefix = kUltraFastTesting ? '[DEV-ULTRA] ' : '[DEV] ';
      }

      // Format the notification message
      final inactivityPeriod = kDevModeEnabled && kUltraFastTesting
          ? '$inactiveHours minutes'
          : '$inactiveHours hours';

      // Send notification with high priority
      await NotificationManager().useBestNotification(
        id: 'inactivity-${responderUid.hashCode}'.hashCode,
        title: '${devModePrefix}Danoggin Inactivity Alert',
        body: '$responderName has been inactive for $inactivityPeriod. ' +
            'Last active at $lastActivityTime$timeZoneInfo.',
        triggerRefresh: true,
      );

      Logger().i('Inactivity alert sent for responder: $responderName');

      // Update tracking
      onAlertSent(alertKey);
    } catch (e) {
      Logger().e('Error sending inactivity alert: $e');
    }
  }
}
