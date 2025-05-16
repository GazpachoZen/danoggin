import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:danoggin/services/notifications/notification_manager.dart';

/// Utility functions for direct notification testing and handling
class NotificationUtils {
  /// Test direct notification delivery
  static Future<void> testDirectNotification() async {
    try {
      print("Testing direct notification...");

      const AndroidNotificationDetails androidPlatformChannelSpecifics =
          AndroidNotificationDetails(
        'danoggin_direct_test', // Channel ID
        'Danoggin Test Channel', // Channel name
        channelDescription: 'Channel for testing notifications',
        importance: Importance.max,
        priority: Priority.high,
        ticker: 'ticker',
      );

      const NotificationDetails platformChannelSpecifics =
          NotificationDetails(android: androidPlatformChannelSpecifics);

      // Generate a unique ID
      final int notificationId = DateTime.now().millisecond;

      await NotificationManager().useBestNotification(
        id: notificationId,
        title: 'Plain Test Notification',
        body: 'This is a simple notification from Danoggin',
        triggerRefresh: false,
      );

      print("Direct test notification sent!");
    } catch (e) {
      print("Error sending direct test notification: $e");
    }
  }

  /// Trigger a specific check-in notification
  static Future<void> triggerCheckInNotification({
    required BuildContext context,
    required String responderUid,
    required String responderName,
    required String result,
    required String timeStr,
    required String checkInId,
    required String? lastNotifiedId,
    required String? lastAcknowledgedId,
    required Function(String) onNotificationSent,
  }) async {
    try {
      // Create a unique key for this check-in
      final checkInKey = "$responderUid:$checkInId";

      // Check if we've already notified for this
      if (checkInKey == lastNotifiedId || checkInKey == lastAcknowledgedId) {
        print("Already notified or acknowledged for check-in: $checkInKey");
        return;
      }

      print("🔔 Preparing to send notification for $responderName");

      // Update tracking
      onNotificationSent(checkInKey);

      // Use direct notification method for more reliable delivery
      const AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
        'danoggin_alerts', // different channel ID
        'Danoggin Urgent Alerts',
        channelDescription:
            'Used for critical alerts about missed or incorrect check-ins',
        importance: Importance.high,
        priority: Priority.high,
        enableVibration: true,
        playSound: true,
        icon: 'ic_stat_warning',
      );

      const NotificationDetails platformDetails =
          NotificationDetails(android: androidDetails);

      // Generate a unique notification ID based on the check-in
      final notificationId = checkInId.hashCode.abs();

      print("🔔 Sending notification with ID: $notificationId");

      // Use the plugin directly
      final FlutterLocalNotificationsPlugin notifications =
          FlutterLocalNotificationsPlugin();

      await NotificationManager().useBestNotification(
        id: notificationId,
        title: 'Danoggin Alert: $result',
        body: '$responderName had a $result check-in at $timeStr',
        triggerRefresh: true,
      );

      print("🔔 Notification sent successfully!");

      // Also show a snackbar in the UI
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Notification sent for $responderName'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e, stackTrace) {
      print("❌ Error sending notification: $e");
      print(stackTrace);

      // Show error in UI
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Notification error: $e'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }
}
