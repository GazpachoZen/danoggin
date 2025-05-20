import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:danoggin/models/user_role.dart';
import 'package:danoggin/screens/settings_page.dart';
import 'package:danoggin/services/notifications/notification_manager.dart';
import 'package:danoggin/controllers/quiz_controller.dart';
import 'package:danoggin/widgets/quiz/question_display.dart';
import 'package:danoggin/widgets/quiz/answer_grid.dart';
import 'package:danoggin/widgets/quiz/feedback_display.dart';
import 'package:danoggin/utils/back_button_handler.dart';
import 'package:danoggin/theme/app_colors.dart';
import 'package:danoggin/screens/logs_viewer_screen.dart';

// Add this near the top of the file, after imports
const bool kDevModeEnabled = true; // Set to false for production

class QuizPage extends StatefulWidget {
  final UserRole currentRole;

  const QuizPage({super.key, required this.currentRole});

  @override
  _QuizPageState createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> with WidgetsBindingObserver {
  late QuizController _controller;
  String _userName = "Responder"; // Default value
  final BackButtonHandler _backButtonHandler = BackButtonHandler();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Initialize the quiz controller
    _controller = QuizController(
      currentRole: widget.currentRole,
      onStateChanged: () {
        if (mounted) setState(() {});
      },
    );

    _controller.initialize();
    _loadUserName();
    _checkNotificationPermissions();

    _setupForegroundNotifications();
  }

  void _setupForegroundNotifications() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      // Use the logging system for iOS debugging
      NotificationManager().log('=== FCM FOREGROUND MESSAGE RECEIVED ===');
      NotificationManager().log('Message ID: ${message.messageId}');
      NotificationManager().log('Title: ${message.notification?.title}');
      NotificationManager().log('Body: ${message.notification?.body}');
      NotificationManager()
          .log('Has notification payload: ${message.notification != null}');
      NotificationManager().log(
          'App in foreground: ${WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed}');
      NotificationManager().log('=== END FCM DEBUG ===');

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
    });

    NotificationManager().log('FCM foreground listener set up successfully');
  }

  @override
  void dispose() {
    _controller.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_controller.isLoading) {
      setState(() {});
    }
  }

  Future<void> _loadUserName() async {
    final name = await _controller.loadUserName();
    if (mounted) {
      setState(() {
        _userName = name;
      });
    }
  }

  Future<void> _checkNotificationPermissions() async {
    // Wait for UI to be fully initialized
    await Future.delayed(Duration(seconds: 2));
    if (!mounted) return;

    // Check if notifications are enabled
    bool enabled = true;
    try {
      enabled = await NotificationManager().areNotificationsEnabled();
    } catch (e) {
      print('❌ Error checking notification permissions: $e');
      return;
    }

    // If notifications are disabled, show a more urgent dialog for responders
    if (!enabled && mounted) {
      showDialog(
        context: context,
        barrierDismissible: false, // User must respond to dialog
        builder: (context) => AlertDialog(
          title: Text('Important: Enable Notifications'),
          content: Text('Notifications appear to be disabled for this app. '
              'As a Responder, you need notifications to be alerted when it\'s time for a check-in.\n\n'
              'Please enable notifications for this app in your device settings to '
              'ensure you receive check-in alerts.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Later'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                // Show manual instructions
                NotificationManager().openNotificationSettings(context);
              },
              child: Text('Show Instructions'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _testNotifications() async {
    try {
      // Set the current context for notifications
      NotificationManager().setCurrentContext(context);

      // Show loading indicator
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Testing FCM notification pipeline...'),
          duration: Duration(seconds: 3),
        ),
      );

      // First ensure we have a valid FCM token
      final token = await FirebaseMessaging.instance.getToken();

      if (token == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to get FCM token'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Test the full FCM pipeline by calling our Cloud Function
      final response = await http.post(
        Uri.parse(
            'https://us-central1-danoggin-d0478.cloudfunctions.net/testFCM'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'token': token,
          'message':
              'Test notification from responder app - FCM pipeline working!',
        }),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'FCM test notification sent successfully!\nCheck your notification tray.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 4),
          ),
        );

        // Log success for debugging
        NotificationManager()
            .log('FCM test notification sent via Cloud Function');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send test notification: ${response.body}'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ),
        );

        // Log failure for debugging
        NotificationManager()
            .log('FCM test failed: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error testing FCM: $e'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 4),
        ),
      );

      // Log error for debugging
      NotificationManager().log('FCM test error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Handle back button press with WillPopScope
    return WillPopScope(
      onWillPop: () =>
          _backButtonHandler.handleBackPress(context, _controller.currentRole),
      child: _controller.isLoading || _controller.currentQuestion == null
          ? _buildLoadingScreen()
          : _buildMainScreen(),
    );
  }

  Widget _buildLoadingScreen() {
    return Scaffold(
      appBar: AppBar(
        title: Text('Danoggin: $_userName'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => _navigateToSettings(),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text("Loading your next question...",
                style: TextStyle(fontSize: 16, color: Colors.grey[700])),
          ],
        ),
      ),
    );
  }

  Widget _buildMainScreen() {
    return Scaffold(
      appBar: _buildAppBar(),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            QuestionDisplay(question: _controller.currentQuestion!),
            SizedBox(height: 24),
            AnswerGrid(
              choices: _controller.displayedChoices,
              selectedAnswer: _controller.selectedAnswer,
              previousIncorrectAnswer: _controller.previousIncorrectAnswer,
              isDisabled: _controller.uiDisabled,
              onAnswerSelected: (answer) {
                _controller.selectAnswer(answer);
                setState(() {});
              },
            ),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed:
                  (_controller.uiDisabled || _controller.selectedAnswer == null)
                      ? null
                      : () => _controller.submitAnswer(),
              style: ElevatedButton.styleFrom(
                // Use midBlue from your color palette for a stronger color
                backgroundColor: _controller.selectedAnswer != null
                    ? AppColors.skyBlue
                    : AppColors.lightGray,
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
                textStyle: TextStyle(
                  fontSize: _controller.selectedAnswer != null
                      ? 20
                      : 16, // Larger font when active
                  fontWeight: FontWeight.bold,
                ),
              ),
              child: Text('Submit'),
            ),
            SizedBox(height: 24),
            FeedbackDisplay(feedback: _controller.feedback),
          ],
        ),
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      title: Text('Danoggin: $_userName'),
      actions: [
        // Dev mode refresh button (if enabled)
        if (kDevModeEnabled)
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Load new question (dev only)',
            onPressed: () {
              _controller.loadRandomQuestion();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Question refreshed (dev mode)'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
          ),
        // Only keep the notification test button
        IconButton(
          icon: const Icon(Icons.notifications),
          tooltip: 'Test FCM Pipeline',
          onPressed: _testNotifications,
        ),
        // Keep the settings button
        IconButton(
          icon: const Icon(Icons.settings),
          onPressed: () => _navigateToSettings(),
        ),
        // Keep the logs viewer button for debugging
        IconButton(
          icon: const Icon(Icons.list),
          tooltip: 'View Logs',
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => LogsViewerScreen(),
              ),
            );
          },
        ),
      ],
    );
  }

  Future<void> _navigateToSettings() async {
    final result = await Navigator.push<dynamic>(
      context,
      MaterialPageRoute(
        builder: (context) =>
            SettingsPage(currentRole: _controller.currentRole),
      ),
    );

    // If result is true (boolean), pack selections or relationships have changed
    if (result == true) {
      // Reload the question packs to reflect new selections
      await _controller.reloadPacks();
      setState(() {}); // Refresh UI
    }
    // Handle role changes
    else if (result != null && result != _controller.currentRole) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('userRole', result.name);
      setState(() {
        _controller.updateRole(result);
      });
    }
  }
}
