import 'dart:async';
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

    // Use the centralized method from NotificationManager
    // This will show one dialog if needed and handle all permission logic
    await NotificationManager().checkAndRequestPermissions(context);
  }

  @override
  Widget build(BuildContext context) {
    // Handle back button press with WillPopScope
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (!didPop) {
          final shouldPop = await _backButtonHandler.handleBackPress(
              context, _controller.currentRole);
          if (shouldPop) {
            Navigator.of(context).pop();
          }
        }
      },
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
            QuestionDisplay(
              question: _controller.currentQuestion!,
              isDisabled: _controller.uiDisabled,
            ),
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
      title: Text(_userName),
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
        // Keep the settings button
        IconButton(
          icon: const Icon(Icons.settings),
          onPressed: () => _navigateToSettings(),
        ),
        // Keep the logs viewer button for debugging
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
