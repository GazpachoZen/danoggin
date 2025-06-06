import 'package:danoggin/utils/logger.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:danoggin/services/notifications/notification_manager.dart';
import 'package:danoggin/models/user_role.dart';
import 'package:danoggin/screens/settings_page.dart';
import 'package:danoggin/screens/quiz_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:danoggin/utils/back_button_handler.dart';
import 'package:danoggin/controllers/observer_controller.dart';
import 'package:danoggin/widgets/observer/responder_selector_widget.dart';
import 'package:danoggin/widgets/observer/check_in_list_widget.dart';

Future<void> requestNotificationPermissions() async {
  // Request permission for notifications
  // final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
  //     FlutterLocalNotificationsPlugin();

  // For Android, there's no explicit permissions request in this version
  // The channel creation handles this automatically
  Logger().i("Notification permission handled through channel creation");
}

class ObserverPage extends StatefulWidget {
  const ObserverPage({super.key});

  @override
  State<ObserverPage> createState() => _ObserverPageState();
}

class _ObserverPageState extends State<ObserverPage> with WidgetsBindingObserver {
  // Controller for managing business logic
  late ObserverController _controller;

  // Back button handler
  final BackButtonHandler _backButtonHandler = BackButtonHandler();

  @override
  void initState() {
    super.initState();
    
    // Add this widget as a lifecycle observer
    WidgetsBinding.instance.addObserver(this);

    // Initialize the controller with state change callback
    _controller = ObserverController(onStateChanged: () {
      if (mounted) setState(() {});
    });

    // Request notification permissions
    requestNotificationPermissions();

    // Initialize the controller
    _controller.initialize();

    _setupForegroundNotifications();

    // Add this line to check notification permissions
    _checkNotificationPermissions();
  }

  @override
  void dispose() {
    // Remove lifecycle observer
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    if (state == AppLifecycleState.resumed) {
      Logger().i('ObserverPage: App came to foreground');
      _handleAppForeground();
    }
  }

  /// Handle app coming to foreground for observers
  Future<void> _handleAppForeground() async {
    try {
      Logger().i('ObserverPage: Handling foreground state');
      
      // For observers, we might want to refresh data or clear stale notifications
      // but we don't need to refresh questions like responders do
      
      // Reload responder data to get fresh information
      await _controller.loadResponders();
      
      // Check for any pending inactivity notifications that might need clearing
      // This ensures the observer sees the most current state
      
      Logger().i('ObserverPage: Foreground handling complete');
    } catch (e) {
      Logger().e('ObserverPage: Error handling foreground: $e');
    }
  }

  void _setupForegroundNotifications() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      // Use the logging system for iOS debugging
      NotificationManager().log('=== FCM FOREGROUND MESSAGE RECEIVED (Observer) ===');
      NotificationManager().log('Message ID: ${message.messageId}');
      NotificationManager().log('Title: ${message.notification?.title}');
      NotificationManager().log('Body: ${message.notification?.body}');
      NotificationManager()
          .log('Has notification payload: ${message.notification != null}');
      NotificationManager().log(
          'App in foreground: ${WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed}');
      NotificationManager().log('=== END FCM DEBUG (Observer) ===');

      if (message.notification != null) {
        NotificationManager().log('Attempting to show system notification...');

        NotificationManager()
            .useBestNotification(
          id: DateTime.now().millisecondsSinceEpoch,
          title: message.notification!.title ?? 'Danoggin',
          body: message.notification!.body ?? 'Test notification',
          triggerRefresh: false,
        )
            .then((success) {
          NotificationManager().log('Notification display result: $success');
        }).catchError((error) {
          NotificationManager().log('Error displaying notification: $error');
        });
      } else {
        NotificationManager().log('No notification payload found');
      }

      // Check if this is an alert notification that should refresh observer data
      final data = message.data;
      if (data['type'] == 'check_in_alert' || data['type'] == 'inactivity_alert') {
        Logger().i('ObserverPage: Received alert notification, refreshing data');
        _controller.loadResponders();
      }
    });

    NotificationManager().log('FCM foreground listener set up successfully (Observer)');
  }

  @override
  Widget build(BuildContext context) {
    // Add WillPopScope to handle back button press
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (!didPop) {
          final shouldPop = await _backButtonHandler.handleBackPress(
              context, UserRole.observer);
          if (shouldPop) {
            Navigator.of(context).pop();
          }
        }
      },
      child: Scaffold(
        appBar: _buildAppBar(),
        body: _buildBody(),
      ),
    );
  }

  // Build the app bar
  AppBar _buildAppBar() {
    return AppBar(
      title: Text('${UserRole.observer.displayLabel} Dashboard'),
      actions: [
        IconButton(
          icon: const Icon(Icons.settings),
          onPressed: _navigateToSettings,
        ),
      ],
    );
  }

  // Build the main body content
  Widget _buildBody() {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height -
            AppBar().preferredSize.height -
            MediaQuery.of(context).padding.top,
      ),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Responder selector (only show if multiple responders)
          if (_controller.responderMap.length > 1)
            ResponderSelectorWidget(
              responderMap: _controller.responderMap,
              selectedResponderUid: _controller.selectedResponderUid,
              onResponderSelected: (uid) => _controller.selectResponder(uid),
            ),

          // Selected responder info header
          if (_controller.selectedResponderUid != null &&
              _controller.responderMap.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: Text(
                'Monitoring: ${_controller.responderMap[_controller.selectedResponderUid] ?? "Unknown"}',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),

          // Check-in list
          Expanded(
            child: CheckInListWidget(
              responderMap: _controller.responderMap,
              selectedResponderUid: _controller.selectedResponderUid,
              lastAcknowledgedId: _controller.lastAcknowledgedId,
              onAcknowledge: (key) => _controller.acknowledge(key),
            ),
          ),
        ],
      ),
    );
  }

  // Navigate to settings page
  Future<void> _navigateToSettings() async {
    final result = await Navigator.push<dynamic>(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsPage(currentRole: UserRole.observer),
      ),
    );

    // If result is a Boolean 'true', relationships have changed
    if (result == true) {
      await _controller.loadResponders(); // Refresh the responder list
    }
    // If result is a UserRole, handle role change
    else if (result != null && result != UserRole.observer) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('userRole', result.name);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => result == UserRole.responder
              ? QuizPage(currentRole: result)
              : ObserverPage(),
        ),
      );
    }
  }

  Future<void> _checkNotificationPermissions() async {
    // Wait for UI to be fully initialized
    await Future.delayed(Duration(seconds: 2));
    if (!mounted) return;

    // Use the centralized method from NotificationManager
    await NotificationManager().checkAndRequestPermissions(context);
  }
}