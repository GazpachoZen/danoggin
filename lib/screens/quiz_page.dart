import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:danoggin/models/question.dart';
import 'package:danoggin/models/answer_option.dart';
import 'package:danoggin/models/question_pack.dart';
import 'package:danoggin/models/user_role.dart';
import 'package:danoggin/services/notification_service.dart';
import 'package:danoggin/screens/settings_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:danoggin/services/auth_service.dart';
import 'package:danoggin/services/notification_helper.dart';
import 'package:danoggin/theme/app_colors.dart';
import 'package:danoggin/services/question_manager.dart';
import 'package:danoggin/services/question_pack_service.dart';

// Add this near the top of the file, after imports
const bool kDevModeEnabled = true; // Set to false for production

class QuizPage extends StatefulWidget {
  final UserRole currentRole;

  const QuizPage({super.key, required this.currentRole});

  @override
  _QuizPageState createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> with WidgetsBindingObserver {
  bool _uiDisabled = false;
  bool _isRetryAttempt = false;
  AnswerOption? _previousIncorrectAnswer;
  bool isLoading = true;
  TimeOfDay? startHour;
  TimeOfDay? endHour;
  Question? currentQuestion;
  List<AnswerOption> displayedChoices = [];
  String _userName = "Responder"; // Default value

  // New variables for multiple question packs
  late QuestionManager questionManager;
  List<QuestionPack> subscribedPacks = [];

  AnswerOption? selectedAnswer;
  String? feedback;

  Timer? alertTimer;
  Timer? responseTimer;

  // Add notification subscription
  late StreamSubscription<dynamic> _notificationSubscription;

  // Will be set based on settings
  Duration alertInterval = Duration(minutes: 5);
  Duration responseTimeout = Duration(minutes: 1);

  late UserRole currentRole;

  // New flag to track if a timeout is already being handled
  bool _timeoutActive = false;

  // Add flag to track initial app load
  bool _isInitialLoad = true;

  Future<void> _loadUserName() async {
    try {
      final uid = AuthService.currentUserId;
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      
      if (userDoc.exists) {
        final userData = userDoc.data();
        if (userData != null && userData.containsKey('name')) {
          setState(() {
            _userName = userData['name'] as String;
          });
        }
      }
    } catch (e) {
      print('Error loading user name: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    // Initialize currentRole from widget parameter
    currentRole = widget.currentRole;

    WidgetsBinding.instance.addObserver(this);
    _loadUserName();
    loadPackFromFirestore();

    // Check notification permissions after a short delay
    _checkNotificationPermissions();

    // Set up notification listener
    _setupNotificationListener();
  }

  // Add method to set up notification listener
  void _setupNotificationListener() {
    // Listen for notification events using a stream
    _notificationSubscription =
        NotificationHelper.notificationEventStream.listen((event) {
      // If app is already open and showing a question, refresh to the new question
      if (mounted && !isLoading && !_isInitialLoad) {
        print('Received notification event, refreshing question');

        // Cancel existing response timer
        responseTimer?.cancel();

        // Reset timeout state
        _timeoutActive = false;

        // Refresh the question without triggering another notification
        setState(() {
          currentQuestion = questionManager.getNextQuestion();
          displayedChoices = currentQuestion!.getShuffledChoices();
          selectedAnswer = null;
          feedback = null;
          _uiDisabled = false;
          _isRetryAttempt = false;
          _previousIncorrectAnswer = null;
        });

        // Set new timeout
        responseTimer?.cancel();
        responseTimer = Timer(responseTimeout, _handleTimeout);

        print('Question refreshed due to notification event');
      }
    });
  }

  // Add this method to check notification permissions
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

  @override
  void dispose() {
    _notificationSubscription.cancel();
    alertTimer?.cancel();
    responseTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !isLoading) {
      setState(() {});
    }
  }

  void _parseOperationHours(String startStr, String endStr) {
    try {
      final startParts = startStr.split(':').map(int.parse).toList();
      final endParts = endStr.split(':').map(int.parse).toList();
      startHour = TimeOfDay(hour: startParts[0], minute: startParts[1]);
      endHour = TimeOfDay(hour: endParts[0], minute: endParts[1]);
    } catch (e) {
      startHour = const TimeOfDay(hour: 8, minute: 0);
      endHour = const TimeOfDay(hour: 20, minute: 0);
    }
  }

  bool _isWithinActiveHours() {
    if (startHour == null || endHour == null) return true;

    final now = TimeOfDay.now();
    final nowMinutes = now.hour * 60 + now.minute;
    final startMinutes = startHour!.hour * 60 + startHour!.minute;
    final endMinutes = endHour!.hour * 60 + endHour!.minute;

    return nowMinutes >= startMinutes && nowMinutes <= endMinutes;
  }

  Future<void> loadPackFromFirestore() async {
    try {
      // Load all subscribed packs instead of just demo_pack
      subscribedPacks = await QuestionPackService.loadSubscribedPacks();
      
      // Create question manager with all packs
      questionManager = QuestionManager(subscribedPacks);
      
      final prefs = await SharedPreferences.getInstance();

      // Don't overwrite currentRole that was set from widget parameter
      // final roleStr = prefs.getString('userRole');
      // currentRole = UserRoleExtension.fromString(roleStr) ?? UserRole.responder;

      final startStr = prefs.getString('startHour') ?? '08:00';
      final endStr = prefs.getString('endHour') ?? '20:00';
      _parseOperationHours(startStr, endStr);
      final frequency = prefs.getDouble('alertFrequency') ?? 5;
      final timeout = prefs.getDouble('timeoutDuration') ?? 1;

      alertInterval = Duration(minutes: frequency.round());
      responseTimeout = Duration(minutes: timeout.round());

      loadRandomQuestion();
      setState(() {
        isLoading = false;
      });
      startAlertLoop();
    } catch (e) {
      print('Error loading packs: $e');
    }
  }

  void startAlertLoop() {
    alertTimer?.cancel();
    alertTimer = Timer.periodic(alertInterval, (_) async {
      final prefs = await SharedPreferences.getInstance();
      final startStr = prefs.getString('startHour') ?? '08:00';
      final endStr = prefs.getString('endHour') ?? '20:00';
      _parseOperationHours(startStr, endStr);

      if (_isWithinActiveHours()) {
        // Check if notifications are enabled
        bool enabled = true;
        try {
          enabled = await NotificationHelper.areNotificationsEnabled();
        } catch (e) {
          print('Error checking notification permissions: $e');
        }

        if (!enabled && mounted) {
          // Show a dialog prompting to enable notifications
          NotificationHelper.showInAppAlert(
            context,
            'Notifications Disabled',
            'Check-in notifications appear to be disabled. This app requires notifications to remind you when it\'s time to perform a check-in. Please enable notifications for the app in your device settings.',
          );
        }

        // Pass isScheduled=true to indicate this is a scheduled alert
        loadRandomQuestion(isScheduled: true);
      }
    });
  }

  void loadRandomQuestion({bool isScheduled = false}) {
    // Use the question manager to get a random question from any pack
    currentQuestion = questionManager.getNextQuestion();
    displayedChoices = currentQuestion!.getShuffledChoices();
    selectedAnswer = null;
    feedback = null;

    // Reset state for new question
    _uiDisabled = false;
    _isRetryAttempt = false;
    _previousIncorrectAnswer = null;
    _timeoutActive = false; // Reset timeout flag for new question

    responseTimer?.cancel();
    responseTimer = Timer(responseTimeout, _handleTimeout);

    // Only show alert with refresh event if it's a scheduled update (not initial load)
    if (isScheduled || !_isInitialLoad) {
      // Use the NotificationHelper to show the check-in notification
      NotificationHelper.showAlert(
        id: 1, // Use 1 as the ID for check-in notifications
        title: 'Danoggin Check-In',
        body: 'Time to answer a quick question!',
        triggerRefresh:
            isScheduled, // Only trigger refresh for scheduled alerts
      );
    } else {
      // First load, just mark that we've completed initial load
      _isInitialLoad = false;
    }
  }

  void _handleTimeout() async {
    // Only handle timeout if it's not already being handled
    if (_timeoutActive) return;

    if (selectedAnswer == null) {
      setState(() {
        _timeoutActive = true; // Mark timeout as active
        feedback = _isRetryAttempt
            ? '⏰ You missed the second chance.'
            : '⏰ You missed the question.';
        _uiDisabled = true; // Disable UI after timeout
      });

      // Log the missed check-in
      await logCheckIn(
        responderId: currentRole.name,
        result: _isRetryAttempt ? 'missed_retry' : 'missed',
        questionPrompt: currentQuestion!.prompt,
      );

      // Cancel any outstanding check-in notifications since we've now handled the timeout
      await NotificationHelper.cancelNotification(
          1); // Use 1 as the ID for check-in notifications

      Future.delayed(Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _timeoutActive = false;
          });
        }
      });
    }
  }

  Future<void> submitAnswer() async {
    if (selectedAnswer == null) return;

    responseTimer?.cancel();

    // Cancel any outstanding check-in notifications to prevent confusion
    await NotificationHelper.cancelNotification(1); // Check-in notification ID

    final isCorrect = selectedAnswer == currentQuestion!.correctAnswer;

    if (isCorrect) {
      // Correct answer case
      setState(() {
        feedback = '✅ Correct!';
        _uiDisabled = true; // Disable UI after correct answer
      });

      await logCheckIn(
        responderId: currentRole.name,
        result: 'correct',
        questionPrompt: currentQuestion!.prompt,
      );

      // Also cancel any missed check-in notifications on successful answer
      await NotificationHelper.cancelNotification(
          2); // Missed check-in notification ID
    } else {
      // Incorrect answer case
      if (!_isRetryAttempt) {
        // First incorrect attempt - allow retry
        _previousIncorrectAnswer = selectedAnswer;
        setState(() {
          feedback = '❌ Incorrect. Try again.';
          selectedAnswer = null;
          _isRetryAttempt = true;
        });

        // Log the first incorrect attempt
        await logCheckIn(
          responderId: currentRole.name,
          result: 'incorrect_first_attempt',
          questionPrompt: currentQuestion!.prompt,
        );

        // Restart the timer for the second attempt
        responseTimer = Timer(responseTimeout, _handleTimeout);
      } else {
        // Second incorrect attempt - disable UI
        setState(() {
          feedback = '❌ Incorrect';
          _uiDisabled = true;
        });

        // Log the final incorrect result
        await logCheckIn(
          responderId: currentRole.name,
          result: 'incorrect',
          questionPrompt: currentQuestion!.prompt,
        );
      }
    }
  }

  // Add method to show question pack progress (for debugging)
  void _showPackProgress() {
    final progress = questionManager.getPacksProgress();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Question Pack Progress'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: subscribedPacks.map((pack) {
            final packInfo = progress[pack.id];
            final completed = packInfo?['completed'] ?? 0;
            final total = packInfo?['total'] ?? 0;
            final percent = total > 0 ? (completed / total * 100).toStringAsFixed(1) : '0';
            
            return ListTile(
              title: Text(pack.name),
              subtitle: Text('$completed / $total questions ($percent%)'),
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Show loading indicator if still loading or question is not initialized
    if (isLoading || currentQuestion == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text('Danoggin: $_userName'),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () async {
                final result = await Navigator.push<dynamic>(
                  context,
                  MaterialPageRoute(
                      builder: (context) =>
                          SettingsPage(currentRole: currentRole)),
                );
                
                // If result is true (boolean), pack selections or relationships have changed
                if (result == true) {
                  // Reload the question packs to reflect new selections
                  await loadPackFromFirestore();
                  setState(() {}); // Refresh UI
                }
                // Handle role changes as before
                else if (result != null && result != currentRole) {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('userRole', result.name);
                  setState(() {
                    currentRole = result;
                  });
                }
              },
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

    // Main UI when question is loaded
    return Scaffold(
      appBar: AppBar(
        title: Text('Danoggin: $_userName'),
        actions: [
          // Add this dev mode refresh button
          if (kDevModeEnabled)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Load new question (dev only)',
              onPressed: () {
                // Cancel existing timers first
                responseTimer?.cancel();
                
                // Load a new question
                loadRandomQuestion();
                
                // Show a snackbar to confirm
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Question refreshed (dev mode)'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
            ),
          // Add debug button to show pack progress in dev mode
          if (kDevModeEnabled)
            IconButton(
              icon: const Icon(Icons.analytics),
              tooltip: 'Show pack progress (dev only)',
              onPressed: _showPackProgress,
            ),
          IconButton(
            icon: const Icon(Icons.notifications),
            tooltip: 'Test Notifications',
            onPressed: _testNotifications,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () async {
              final result = await Navigator.push<dynamic>(
                context,
                MaterialPageRoute(
                    builder: (context) =>
                        SettingsPage(currentRole: currentRole)),
              );
              
              // If result is true (boolean), pack selections or relationships have changed
              if (result == true) {
                // Reload the question packs to reflect new selections
                await loadPackFromFirestore();
                setState(() {}); // Refresh UI
              }
              // Handle role changes as before
              else if (result != null && result != currentRole) {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('userRole', result.name);
                setState(() {
                  currentRole = result;
                });
              }
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(currentQuestion!.prompt, style: TextStyle(fontSize: 24)),
            SizedBox(height: 24),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.0,
              children: displayedChoices.map((answer) {
                final isSelected = selectedAnswer == answer;
                final isPreviousIncorrect = answer == _previousIncorrectAnswer;
                final isDisabled = _uiDisabled || isPreviousIncorrect;

                return ElevatedButton(
                  onPressed: isDisabled
                      ? null
                      : () {
                          setState(() {
                            selectedAnswer = answer;
                            feedback = null;
                          });
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isSelected ? AppColors.coral : AppColors.lightGray,
                    padding: EdgeInsets.all(4),
                    disabledBackgroundColor: isPreviousIncorrect
                        ? Colors.red.withOpacity(0.3)
                        : null,
                  ),
                  child: answer.render(disabled: isDisabled),
                );
              }).toList(),
            ),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: (_uiDisabled || selectedAnswer == null) ? null : submitAnswer,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.midBlue,
                foregroundColor: AppColors.offWhite,
              ),
              child: Text('Submit'),
            ),
            SizedBox(height: 24),
            if (feedback != null)
              Text(
                feedback!,
                style: TextStyle(
                  fontSize: 20,
                  color: feedback == '✅ Correct!'
                      ? Colors.green
                      : (feedback == '❌ Incorrect. Try again.'
                          ? Colors.orange
                          : Colors.red),
                ),
              ),
          ],
        ),
      ),
    );
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
}

Future<void> logCheckIn({
  required String responderId,
  required String result,
  required String questionPrompt,
}) async {
  try {
    final now = DateTime.now();

    // Get the current user's UID from AuthService
    final uid = AuthService.currentUserId;

    print(
        "SAVE: Writing check-in data to responder_status/$uid/check_ins/${now.toIso8601String()}");
    print(
        "SAVE: Data: result=$result, prompt=$questionPrompt, timestamp=${now.toIso8601String()}");

    final doc = FirebaseFirestore.instance
        .collection('responder_status')
        .doc(uid) // Use the actual UID instead of static responderId
        .collection('check_ins')
        .doc(now.toIso8601String());

    await doc.set({
      'timestamp': now.toIso8601String(),
      'result': result,
      'prompt': questionPrompt,
      'responderId':
          responderId, // Keep this for backward compatibility/filtering
    });

    print("SAVE: Successfully wrote check-in data!");
  } catch (e, stackTrace) {
    print("ERROR: Failed to log check-in: $e");
    print("Stack trace: $stackTrace");
  }
}