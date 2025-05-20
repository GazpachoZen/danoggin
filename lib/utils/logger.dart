// lib/utils/logger.dart
import 'dart:collection';
import 'package:logging/logging.dart' as dart_logging;

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
  
  // Callback function for external integrations
  Function(String, LogLevel)? _onLogCallback;
  
  // Internal Dart logger
  final dart_logging.Logger _dartLogger = dart_logging.Logger('Danoggin');
  
  Logger._internal() {
    // Initialize the Dart logging system
    dart_logging.hierarchicalLoggingEnabled = true;
    _dartLogger.level = dart_logging.Level.INFO;
    
    dart_logging.Logger.root.onRecord.listen((record) {
      Logger().i('${record.level.name}: ${record.time}: ${record.message}');
    });
  }
  
  /// Set the current log level
  void setLogLevel(LogLevel level) {
    _currentLevel = level;
    
    // Update the Dart logger level too
    switch (level) {
      case LogLevel.verbose:
        _dartLogger.level = dart_logging.Level.FINEST;
        break;
      case LogLevel.debug:
        _dartLogger.level = dart_logging.Level.FINE;
        break;
      case LogLevel.info:
        _dartLogger.level = dart_logging.Level.INFO;
        break;
      case LogLevel.warning:
        _dartLogger.level = dart_logging.Level.WARNING;
        break;
      case LogLevel.error:
        _dartLogger.level = dart_logging.Level.SEVERE;
        break;
      case LogLevel.none:
        _dartLogger.level = dart_logging.Level.OFF;
        break;
    }
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
    
    // Call callback if registered
    if (_onLogCallback != null) {
      _onLogCallback!(logMessage, level);
    }
    
    // Also log to the Dart logger
    switch (level) {
      case LogLevel.verbose:
        _dartLogger.finest(message);
        break;
      case LogLevel.debug:
        _dartLogger.fine(message);
        break;
      case LogLevel.info:
        _dartLogger.info(message);
        break;
      case LogLevel.warning:
        _dartLogger.warning(message);
        break;
      case LogLevel.error:
        _dartLogger.severe(message);
        break;
      case LogLevel.none:
        // Do nothing
        break;
    }
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
  
  /// Generic log method (for backward compatibility, logs at INFO level)
  // void log(String message) {
  //   _logWithLevel(message, LogLevel.info);
  // }
  
  /// Get all logs as a list
  List<String> get logs => List.from(_logMessages);
  
  /// Clear all logs
  void clearLogs() {
    _logMessages.clear();
  }
  
  /// Register a callback to be notified when new logs are added
  void setLogCallback(Function(String, LogLevel) callback) {
    _onLogCallback = callback;
  }
  
  /// Remove the callback
  void removeLogCallback() {
    _onLogCallback = null;
  }
}