// lib/utils/logger.dart
import 'dart:collection';

/// Log levels for controlling verbosity
enum LogLevel {
  verbose,  // Most detailed (similar to TRACE in Python)
  debug,    // Debugging information
  info,     // General information
  warning,  // Warnings
  error,    // Errors
  none      // No logging
}

/// Centralized logging utility for the Danoggin app
class Logger {
  // Singleton instance
  static final Logger _instance = Logger._internal();
  factory Logger() => _instance;
  
  // Logging queue
  final Queue<String> _logMessages = Queue<String>();
  static const int _maxLogMessages = 200;
  
  // Default log level
  LogLevel _currentLevel = LogLevel.info;
  
  Logger._internal();
  
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
    
    // Add to our queue with a maximum size
    _logMessages.add(logMessage);
    while (_logMessages.length > _maxLogMessages) {
      _logMessages.removeFirst();
    }
    
    // Print to console for development visibility
    print(logMessage);
  }
  
  /// Convenience methods for different log levels
  
  /// Log a verbose message (most detailed)
  void v(String message) {
    _logWithLevel(message, LogLevel.verbose);
  }
  
  /// Log a debug message
  void d(String message) {
    _logWithLevel(message, LogLevel.debug);
  }
  
  /// Log an info message
  void i(String message) {
    _logWithLevel(message, LogLevel.info);
  }
  
  /// Log a warning message
  void w(String message) {
    _logWithLevel(message, LogLevel.warning);
  }
  
  /// Log an error message
  void e(String message) {
    _logWithLevel(message, LogLevel.error);
  }
  
  /// Get all logs as a list
  List<String> get logs => List.from(_logMessages);
  
  /// Clear all logs
  void clearLogs() {
    _logMessages.clear();
  }
}