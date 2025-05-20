// lib/utils/log_helper.dart
import 'package:flutter/material.dart';
import 'package:danoggin/services/log_service.dart';

class LogHelper {
  /// Email logs without showing the logs UI
  static Future<void> emailLogsWithoutViewer(BuildContext context) async {
    try {
      // Show loading indicator
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Preparing logs for support team...'),
          duration: Duration(seconds: 2),
        ),
      );
      
      // Use the LogService to send logs via email
      final result = await LogService().emailLogs(context);
      
      if (result && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Opening email app with logs'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error preparing logs: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}