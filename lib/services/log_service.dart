// lib/services/log_service.dart
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:danoggin/services/auth_service.dart';
import 'dart:io';

/// Log levels for controlling verbosity
enum LogLevel {
  verbose,  // Most detailed
  debug,
  info,     // Default
  warning,
  error,
  none      // No logging
}

/// Centralized logging utility for the Danoggin app
class LogService {
  // Singleton instance
  static final LogService _instance = LogService._internal();
  factory LogService() => _instance;
  
  // Logging queue
  final Queue<String> _logMessages = Queue<String>();
  static const int _maxLogMessages = 200;
  
  // Default log level
  LogLevel _currentLevel = LogLevel.info;
  
  // Default support email
  String _supportEmail = "support@your-domain.com"; // Replace with actual email
  
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
    _currentLevel = level;
  }
  
  /// Get the current log level
  LogLevel get logLevel => _currentLevel;
  
  /// Log a message with timestamp and level
  void _logWithLevel(String message, LogLevel level) {
    // Skip if the message level is below current level
    if (level.index < _currentLevel.index) {
      return;
    }
    
    final timestamp = DateTime.now().toString().substring(0, 19);
    final levelName = level.toString().split('.').last.toUpperCase();
    final logMessage = "$timestamp [$levelName]: $message";
    
    print(logMessage);
    
    // Add to our queue with a maximum size
    _logMessages.add(logMessage);
    while (_logMessages.length > _maxLogMessages) {
      _logMessages.removeFirst();
    }
  }
  
  /// Get logs filtered by current level
  List<String> getFilteredLogs(LogLevel filterLevel) {
    if (filterLevel == LogLevel.none) {
      return []; // No logs should be shown
    } else if (filterLevel == LogLevel.verbose) {
      return List.from(_logMessages); // Show all logs
    } else {
      // Filter logs based on their level
      return _logMessages.where((log) {
        // Extract the log level from the log string
        if (log.contains('[ERROR]')) {
          return LogLevel.error.index >= filterLevel.index;
        } else if (log.contains('[WARNING]')) {
          return LogLevel.warning.index >= filterLevel.index;
        } else if (log.contains('[INFO]')) {
          return LogLevel.info.index >= filterLevel.index;
        } else if (log.contains('[DEBUG]')) {
          return LogLevel.debug.index >= filterLevel.index;
        } else if (log.contains('[VERBOSE]')) {
          return LogLevel.verbose.index >= filterLevel.index;
        } else {
          // Default to INFO level for logs without explicit level
          return LogLevel.info.index >= filterLevel.index;
        }
      }).toList();
    }
  }
  
  /// Convenience methods for different log levels
  void v(String message) {
    _logWithLevel(message, LogLevel.verbose);
  }
  
  void d(String message) {
    _logWithLevel(message, LogLevel.debug);
  }
  
  void i(String message) {
    _logWithLevel(message, LogLevel.info);
  }
  
  void w(String message) {
    _logWithLevel(message, LogLevel.warning);
  }
  
  void e(String message) {
    _logWithLevel(message, LogLevel.error);
  }
  
  /// Generic log method (for backward compatibility, logs at INFO level)
  void log(String message) {
    _logWithLevel(message, LogLevel.info);
  }
  
  /// Get all logs as a list
  List<String> get logs => List.from(_logMessages);
  
  /// Clear all logs
  void clearLogs() {
    _logMessages.clear();
  }
  
  /// Format and send logs via email
  Future<bool> emailLogs(BuildContext context) async {
    LogLevel filterLevel = logLevel;
    List<String> filteredLogs = getFilteredLogs(filterLevel);
    
    if (filteredLogs.isEmpty) {
      return false;
    }

    try {
      // Gather comprehensive context information
      Map<String, String> contextInfo = await _gatherContextInformation();
      
      // Format logs for email body
      final formattedLogs = filteredLogs.join('\n');
      
      // Format the context information
      final formattedContext = _formatContextInfoForEmail(contextInfo);
      
      // Create email body with context information
      final emailBody = '''
Hi Support Team,

Here are my Danoggin app logs:

$formattedContext

=== LOGS ===
$formattedLogs

[Add any additional information about the issue here]
''';

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
              'Could not open an email app automatically. You can manually send the logs to: $_supportEmail'
            ),
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
      contextInfo['Platform'] = Platform.isAndroid ? 'Android' : (Platform.isIOS ? 'iOS' : 'Unknown');
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
      contextInfo['App Version'] = '${packageInfo.version}+${packageInfo.buildNumber}';
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
      } else if (key.contains('Log') || 
                key.contains('Report')) {
        categories['LOG INFORMATION']![key] = value;
      } else {
        // Default to user information for anything uncategorized
        categories['USER INFORMATION']![key] = value;
      }
    });
    
    // Format each category
    StringBuffer buffer = StringBuffer();
    categories.forEach((category, items) {
      if (items.isNotEmpty) {
        buffer.writeln('=== $category ===');
        items.forEach((key, value) {
          buffer.writeln('$key: $value');
        });
        buffer.writeln();
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
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      
      if (userDoc.exists) {
        final userData = userDoc.data();
        if (userData != null) {
          // Add user details
          userInfo['Name'] = userData['name'] ?? 'Unknown';
          userInfo['Role'] = userData['role'] ?? 'Unknown';
          
          // Add more user details as needed
          // (Role-specific info, timestamps, etc.)
          // Same implementation as in the previous example
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
    final emailUri = Uri(
      scheme: 'mailto',
      path: _supportEmail,
      query: _encodeQueryParameters({
        'subject': 'Danoggin Log Report',
        'body': emailBody
      })
    );
    
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
        .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');
  }
}
