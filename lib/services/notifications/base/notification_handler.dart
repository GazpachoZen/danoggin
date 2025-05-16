import 'dart:async';

/// Interface for handling notification events
abstract class NotificationHandler {
  /// Stream of notification events
  Stream<dynamic> get notificationEvents;

  /// Add a notification event
  void addNotificationEvent(Map<String, dynamic> event);

  /// Clean up resources
  void dispose();
}

/// Default implementation of NotificationHandler
class DefaultNotificationHandler implements NotificationHandler {
  // Stream controller for notification events
  final StreamController<dynamic> _notificationStreamController =
      StreamController<dynamic>.broadcast();

  @override
  Stream<dynamic> get notificationEvents => _notificationStreamController.stream;

  @override
  void addNotificationEvent(Map<String, dynamic> event) {
    _notificationStreamController.add(event);
  }

  @override
  void dispose() {
    _notificationStreamController.close();
  }
}