import 'package:intl/intl.dart';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:danoggin/services/auth_service.dart';
import 'package:danoggin/utils/logger.dart';
import 'dart:io';

/// Log levels for controlling verbosity
/// Using the same LogLevel enum from Logger to avoid confusion
// typedef LogLevel = Logger.LogLevel;

/// Centralized logging utility for the Danoggin app
class LogService {
  // Singleton instance
  static final LogService _instance = LogService._internal();
  factory LogService() => _instance;

  // Use the Logger singleton
  final Logger _logger = Logger();

  // Default support email
  String _supportEmail =
      "bluevista+danoggin@gmail.com"; // Replace with actual email

  // String representations for log levels (for nice display)
  final Map<LogLevel, String> _logLevelNames = {
    LogLevel.verbose: 'Verbose',
    LogLevel.debug: 'Debug',
    LogLevel.info: 'Info',
    LogLevel.warning: 'Warning',
    LogLevel.error: 'Error',
    LogLevel.none: 'None',
  };

  LogService._internal();

  /// Set the support email address
  void setSupportEmail(String email) {
    _supportEmail = email;
  }

  /// Get the current support email address
  String get supportEmail => _supportEmail;

  /// Get readable name for a log level
  String getLevelName(LogLevel level) {
    return _logLevelNames[level] ?? level.toString().split('.').last;
  }

  /// Set the current log level
  void setLogLevel(LogLevel level) {
    _logger.setLogLevel(level);
  }

  /// Get the current log level
  LogLevel get logLevel => _logger.logLevel;

  /// Convenience methods for different log levels

  /// Log a verbose message (most detailed)
  void v(String message) {
    _logger.v(message);
  }

  /// Log a debug message
  void d(String message) {
    _logger.d(message);
  }

  /// Log an info message
  void i(String message) {
    _logger.i(message);
  }

  /// Log a warning message
  void w(String message) {
    _logger.w(message);
  }

  /// Log an error message
  void e(String message) {
    _logger.e(message);
  }

  /// Generic log method (for backward compatibility, logs at INFO level)
  void log(String message) {
    _logger.i(message);
  }

  /// Get all logs as a list
  List<String> get logs => _logger.logs;

  /// Get logs filtered by current level
  List<String> getFilteredLogs(LogLevel filterLevel) {
    if (filterLevel == LogLevel.none) {
      return []; // No logs should be shown
    } else if (filterLevel == LogLevel.verbose) {
      return _logger.logs; // Show all logs
    } else {
      // Filter logs based on their level
      return _logger.logs.where((log) {
        // Extract the log level from the log string
        if (log.contains("[ERROR]")) {
          return LogLevel.error.index >= filterLevel.index;
        } else if (log.contains("[WARNING]")) {
          return LogLevel.warning.index >= filterLevel.index;
        } else if (log.contains("[INFO]")) {
          return LogLevel.info.index >= filterLevel.index;
        } else if (log.contains("[DEBUG]")) {
          return LogLevel.debug.index >= filterLevel.index;
        } else if (log.contains("[VERBOSE]")) {
          return LogLevel.verbose.index >= filterLevel.index;
        } else {
          // Default to INFO level for logs without explicit level
          return LogLevel.info.index >= filterLevel.index;
        }
      }).toList();
    }
  }

  /// Clear all logs
  void clearLogs() {
    _logger.clearLogs();
  }

  /// Format and send logs via email
  Future<bool> emailLogs(BuildContext context) async {
    LogLevel filterLevel = logLevel;
    final lineBreak = Platform.isIOS ? '\r\n' : '\n';

    List<String> filteredLogs = getFilteredLogs(filterLevel);

    if (filteredLogs.isEmpty) {
      return false;
    }

    try {
      // Gather comprehensive context information
      Map<String, String> contextInfo = await _gatherContextInformation();

      // Format logs for email body with platform-appropriate line breaks
      final lb = Platform.isIOS ? '\r\n' : '\n';
      final formattedLogs = filteredLogs.join(lb);

      // Format the context information
      final formattedContext = _formatContextInfoForEmail(contextInfo);

      // Create email body with context information
      final emailBody = "Hi Support Team,$lb$lb"
      + "[   Please use this space to tell us what went wrong    ]$lb"
      + "[The more detail you can provide, the better we can help]$lb$lb"
      + "==========================================================$lb"
      + "$formattedContext"
      + "=== LOGS ===$lb"
      + "$formattedLogs";

      // Try to launch email client
      bool launched = await _launchEmailClient(emailBody);

      if (!launched) {
        throw 'Could not launch email client';
      }

      return true;
    } catch (e) {
      print("Email logs error: $e");

      // Show error message if a context is provided
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sending logs: $e'),
            backgroundColor: Colors.red,
          ),
        );

        // Show guidance about manual email
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Email Client Not Available'),
            content: Text(
                'Could not open an email app automatically. You can manually send the logs to: $_supportEmail'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('OK'),
              ),
            ],
          ),
        );
      }

      return false;
    }
  }

  // Helper method to gather context information
  Future<Map<String, String>> _gatherContextInformation() async {
    Map<String, String> contextInfo = {};

    // Device information
    try {
      contextInfo['Platform'] =
          Platform.isAndroid ? 'Android' : (Platform.isIOS ? 'iOS' : 'Unknown');
      contextInfo['OS Version'] = Platform.operatingSystemVersion;
      contextInfo['Device Locale'] = Platform.localeName;
      contextInfo['UTC Offset'] = DateTime.now().timeZoneOffset.toString();
    } catch (e) {
      contextInfo['Device Info Error'] = e.toString();
    }

    // App version
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      contextInfo['App Name'] = packageInfo.appName;
      contextInfo['App Version'] =
          '${packageInfo.version}+${packageInfo.buildNumber}';
      contextInfo['Package Name'] = packageInfo.packageName;
    } catch (e) {
      contextInfo['App Version Error'] = e.toString();
    }

    // User information
    try {
      contextInfo.addAll(await _getUserInformation());
    } catch (e) {
      contextInfo['User Info Error'] = e.toString();
    }

    // Log information
    contextInfo['Log Level'] = getLevelName(logLevel);
    contextInfo['Total Logs'] = logs.length.toString();
    contextInfo['Filtered Logs'] = getFilteredLogs(logLevel).length.toString();
    contextInfo['Report Time'] = DateTime.now().toString();

    return contextInfo;
  }

  // Format context information for email
  String _formatContextInfoForEmail(Map<String, String> contextInfo) {
    // Categorize information
    Map<String, Map<String, String>> categories = {
      'USER INFORMATION': {},
      'DEVICE INFORMATION': {},
      'APP INFORMATION': {},
      'LOG INFORMATION': {},
    };

    // Sort information into categories
    contextInfo.forEach((key, value) {
      if (key.contains('User') ||
          key.contains('Role') ||
          key.contains('Name') ||
          key.contains('Observer') ||
          key.contains('Check-in')) {
        categories['USER INFORMATION']![key] = value;
      } else if (key.contains('Platform') ||
          key.contains('Device') ||
          key.contains('OS') ||
          key.contains('Locale') ||
          key.contains('Time Zone') ||
          key.contains('UTC')) {
        categories['DEVICE INFORMATION']![key] = value;
      } else if (key.contains('App') ||
          key.contains('Package') ||
          key.contains('Version')) {
        categories['APP INFORMATION']![key] = value;
      } else if (key.contains('Log') || key.contains('Report')) {
        categories['LOG INFORMATION']![key] = value;
      } else {
        // Default to user information for anything uncategorized
        categories['USER INFORMATION']![key] = value;
      }
    });

    // Format each category
    StringBuffer buffer = StringBuffer();
    final lb = Platform.isIOS ? '\r\n' : '\n';
    categories.forEach((category, items) {
      if (items.isNotEmpty) {
        buffer.write('=== $category ===$lb');
        items.forEach((key, value) {
          buffer.write('$key: $value$lb');
        });
        buffer.write(lb);
      }
    });

    return buffer.toString();
  }

  // Helper method to get user information
  Future<Map<String, String>> _getUserInformation() async {
    final Map<String, String> userInfo = {};

    try {
      final uid = AuthService.currentUserId;
      userInfo['User ID'] = uid;

      // Get user document from Firestore
      final userDoc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();

      if (userDoc.exists) {
        final userData = userDoc.data();
        if (userData != null) {
          // Add user details
          userInfo['Name'] = userData['name'] ?? 'Unknown';
          userInfo['Role'] = userData['role'] ?? 'Unknown';

          // Add more user details as needed
          // (Role-specific info, timestamps, etc.)
        }
      }
    } catch (e) {
      userInfo['Error'] = e.toString();
    }

    return userInfo;
  }

  // Helper method to launch email client
  Future<bool> _launchEmailClient(String emailBody) async {
    // Create the mailto URI
    final now = DateTime.now();
    final formatter = DateFormat('yyMMdd-HHmmss');
    final String timeStamp = formatter.format(now);

    final emailUri = Uri(
        scheme: 'mailto',
        path: _supportEmail,
        query: _encodeQueryParameters(
            {'subject': 'Danoggin Log Report ($timeStamp)', 'body': emailBody}));

    print("Email URI: ${emailUri.toString()}");

    // Try different launch approaches
    try {
      // First try standard launch
      if (await canLaunchUrl(emailUri)) {
        return await launchUrl(emailUri);
      }

      // If that fails, try with explicit mode
      return await launchUrl(
        emailUri,
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      print("Error launching URL: $e");
      return false;
    }
  }

  // Helper function to encode query parameters
  String? _encodeQueryParameters(Map<String, String> params) {
    return params.entries
        .map((e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');
  }
}
