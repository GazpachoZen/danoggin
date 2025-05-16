import 'dart:collection';

/// Handles logging for the notification system
class NotificationLogger {
  // Singleton instance
  static final NotificationLogger _instance = NotificationLogger._internal();
  factory NotificationLogger() => _instance;
  NotificationLogger._internal();

  // Logging queue
  final Queue<String> _logMessages = Queue<String>();
  static const int _maxLogMessages = 100;

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
  }

  /// Get all logs as a list
  List<String> get logs => List.from(_logMessages);

  /// Clear all logs
  void clearLogs() {
    _logMessages.clear();
  }
}