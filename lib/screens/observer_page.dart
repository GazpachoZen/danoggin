import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
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
  print("Notification permission handled through channel creation");
}

class ObserverPage extends StatefulWidget {
  const ObserverPage({super.key});

  @override
  State<ObserverPage> createState() => _ObserverPageState();
}

class _ObserverPageState extends State<ObserverPage> {
  // Controller for managing business logic
  late ObserverController _controller;

  // Back button handler
  final BackButtonHandler _backButtonHandler = BackButtonHandler();

  @override
  void initState() {
    super.initState();

    // Initialize the controller with state change callback
    _controller = ObserverController(onStateChanged: () {
      if (mounted) setState(() {});
    });

    // Request notification permissions
    requestNotificationPermissions();

    // Initialize the controller
    _controller.initialize();

    _setupForegroundNotifications();
  }

void _setupForegroundNotifications() {
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    // Use the logging system for iOS debugging
    NotificationManager().log('=== FCM FOREGROUND MESSAGE RECEIVED ===');
    NotificationManager().log('Message ID: ${message.messageId}');
    NotificationManager().log('Title: ${message.notification?.title}');
    NotificationManager().log('Body: ${message.notification?.body}');
    NotificationManager().log('Has notification payload: ${message.notification != null}');
    NotificationManager().log('App in foreground: ${WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed}');
    NotificationManager().log('=== END FCM DEBUG ===');
    
    if (message.notification != null) {
      NotificationManager().log('Attempting to show system notification...');
      
      NotificationManager().useBestNotification(
        id: DateTime.now().millisecondsSinceEpoch,
        title: message.notification!.title ?? 'Danoggin',
        body: message.notification!.body ?? 'Test notification',
        triggerRefresh: false,
        forceSystemNotification: true,
      ).then((success) {
        NotificationManager().log('Notification display result: $success');
      }).catchError((error) {
        NotificationManager().log('Error displaying notification: $error');
      });
    } else {
      NotificationManager().log('No notification payload found');
    }
  });
  
  NotificationManager().log('FCM foreground listener set up successfully');
}

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Add WillPopScope to handle back button press
    return WillPopScope(
      onWillPop: () =>
          _backButtonHandler.handleBackPress(context, UserRole.observer),
      child: Scaffold(
        appBar: _buildAppBar(),
        body: _buildBody(),
      ),
    );
  }

  // Build the app bar
  AppBar _buildAppBar() {
    return AppBar(
      title: const Text('Observer Dashboard'),
      actions: [
        IconButton(
          icon: const Icon(Icons.notifications),
          tooltip: 'Test Notifications',
          onPressed: () => _controller.testNotifications(context),
        ),
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
}
