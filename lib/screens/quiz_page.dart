import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:danoggin/models/user_role.dart';
import 'package:danoggin/screens/settings_page.dart';
import 'package:danoggin/services/notification_helper.dart';
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
      enabled = await NotificationHelper.areNotificationsEnabled();
    } catch (e) {
      print('Error checking notification permissions: $e');
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
                NotificationHelper.openNotificationSettings(context);
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
      // Try to check if notifications are enabled
      bool enabled = true;
      try {
        enabled = await NotificationHelper.areNotificationsEnabled();
      } catch (e) {
        print('Error checking notification permissions: $e');
        // If we can't check, assume they're enabled
      }

      if (!enabled) {
        // Show manual instructions if notifications are disabled
        NotificationHelper.openNotificationSettings(context);
        return;
      }

      // Test notification
      await NotificationHelper.testNotification();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Test notification sent!'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      print('Error testing notifications: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error sending test notification: $e'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
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
                // Use coral from your color palette for a stronger color
                backgroundColor: _controller.selectedAnswer != null
                    ? AppColors.coral
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
        // Add this dev mode refresh button
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
        // Remove the debug button that shows pack progress
        IconButton(
          icon: const Icon(Icons.notifications),
          tooltip: 'Test Notifications',
          onPressed: _testNotifications,
        ),
        IconButton(
          icon: const Icon(Icons.settings),
          onPressed: () => _navigateToSettings(),
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
