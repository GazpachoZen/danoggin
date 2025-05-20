// lib/utils/logger.dart
import 'dart:collection';

/// Centralized logging utility for the Danoggin app
class Logger {
  // Singleton instance
  static final Logger _instance = Logger._internal();
  factory Logger() => _instance;
  Logger._internal();

  // Logging queue
  final Queue<String> _logMessages = Queue<String>();
  static const int _maxLogMessages = 200;
  
  // Callback function for external integrations
  Function(String)? _onLogCallback;

  /// Log a message with timestamp
  void log(String message) {
    final timestamp = DateTime.now().toString().substring(0, 19);
    final logMessage = "$timestamp: $message";
    print(logMessage);

    // Add to our queue with a maximum size
    _logMessages.add(logMessage);
    while (_logMessages.length > _maxLogMessages) {
      _logMessages.removeFirst();
    }
    
    // Call callback if registered
    if (_onLogCallback != null) {
      _onLogCallback!(logMessage);
    }
  }

  /// Get all logs as a list
  List<String> get logs => List.from(_logMessages);

  /// Clear all logs
  void clearLogs() {
    _logMessages.clear();
  }
  
  /// Register a callback to be notified when new logs are added
  void setLogCallback(Function(String) callback) {
    _onLogCallback = callback;
  }
  
  /// Remove the callback
  void removeLogCallback() {
    _onLogCallback = null;
  }
}