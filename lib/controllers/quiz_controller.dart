import 'package:danoggin/services/sound_service.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:danoggin/models/user_role.dart';
import 'package:danoggin/models/question.dart';
import 'package:danoggin/models/answer_option.dart';
import 'package:danoggin/models/question_pack.dart';
import 'package:danoggin/services/auth_service.dart';
import 'package:danoggin/services/question_manager.dart';
import 'package:danoggin/services/question_pack_service.dart';
import 'package:danoggin/services/notifications/notification_manager.dart';
import 'package:danoggin/services/check_in_scheduler.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:danoggin/utils/logger.dart';

class QuizController {
  // State variables
  bool isLoading = true;
  bool uiDisabled = false;
  bool isRetryAttempt = false;
  AnswerOption? previousIncorrectAnswer;
  UserRole currentRole;
  Question? currentQuestion;
  List<AnswerOption> displayedChoices = [];
  AnswerOption? selectedAnswer;
  String? feedback;
  List<QuestionPack> subscribedPacks = [];
  final SoundService _soundService = SoundService();

  // Operational settings
  TimeOfDay? startHour;
  TimeOfDay? endHour;
  Duration alertInterval = Duration(minutes: 5);
  Duration responseTimeout = Duration(minutes: 1);

  // Timers
  Timer? responseTimer;

  // Notification subscription
  late StreamSubscription<dynamic> _notificationSubscription;

  // Manager for question handling
  late QuestionManager questionManager;

  // Flags
  bool _timeoutActive = false;
  bool _isInitialLoad = true;
  
  // Track question loading time for staleness detection
  DateTime? _questionLoadedAt;

  // Callback to notify parent of state changes
  final VoidCallback onStateChanged;

  QuizController({
    required this.currentRole,
    required this.onStateChanged,
  });

  // Initialize the controller
  Future<void> initialize() async {
    // Set up notification listener
    _setupFCMMessageListener();
    await _soundService.initialize();
    // Load question packs and initialize
    await loadPackFromFirestore();
  }

  void dispose() {
    _notificationSubscription.cancel();
    responseTimer?.cancel();
  }

  void updateRole(UserRole role) {
    currentRole = role;
    onStateChanged();
  }

  // Check if app should refresh question when coming to foreground
  Future<void> handleAppForeground() async {
    Logger().i('QuizController: App came to foreground, checking for stale question');
    
    // Skip if still in initial loading
    if (isLoading || _isInitialLoad) {
      Logger().i('QuizController: Skipping foreground check - still loading');
      return;
    }

    // Check if there are pending check-in notifications by looking at scheduled time
    try {
      final nextCheckInTime = await CheckInScheduler.getNextCheckInTime();
      if (nextCheckInTime != null) {
        final now = DateTime.now();
        final timeoutMinutes = responseTimeout.inMinutes;
        
        // Check if we're within a check-in window (past due time but within timeout)
        final dueTime = nextCheckInTime;
        final expireTime = nextCheckInTime.add(Duration(minutes: timeoutMinutes));
        
        if (now.isAfter(dueTime) && now.isBefore(expireTime)) {
          // We're in an active check-in window
          Logger().i('QuizController: Active check-in window detected on foreground');
          
          // Check if current question is stale (loaded before the due time)
          if (_questionLoadedAt != null && _questionLoadedAt!.isBefore(dueTime)) {
            Logger().i('QuizController: Current question is stale, refreshing');
            await _refreshQuestionWithFeedback('Check-in refreshed');
          }
        }
      }
    } catch (e) {
      Logger().e('QuizController: Error checking for stale question on foreground: $e');
    }
  }

  // Methods to handle loading data
  Future<String> loadUserName() async {
    try {
      final uid = AuthService.currentUserId;
      final userDoc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();

      if (userDoc.exists) {
        final userData = userDoc.data();
        if (userData != null && userData.containsKey('name')) {
          return userData['name'] as String;
        }
      }
    } catch (e) {
      Logger().e('Error loading user name: $e');
    }
    return "Responder";
  }

  Future<void> loadPackFromFirestore() async {
    try {
      // Load all subscribed packs
      subscribedPacks = await QuestionPackService.loadSubscribedPacks();

      // Create question manager with all packs
      questionManager = QuestionManager(subscribedPacks);

      final prefs = await SharedPreferences.getInstance();

      final startStr = prefs.getString('startHour') ?? '08:00';
      final endStr = prefs.getString('endHour') ?? '20:00';
      _parseOperationHours(startStr, endStr);
      final frequency = prefs.getDouble('alertFrequency') ?? 5;
      final timeout = prefs.getDouble('timeoutDuration') ?? 1;

      alertInterval = Duration(minutes: frequency.round());
      responseTimeout = Duration(minutes: timeout.round());

      loadRandomQuestion();
      isLoading = false;
      onStateChanged();
    } catch (e) {
      Logger().e('Error loading packs: $e');
    }
  }

  Future<void> reloadPacks() async {
    isLoading = true;
    onStateChanged();
    await loadPackFromFirestore();
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

  void loadRandomQuestion({bool isScheduled = false}) {
    // Use the question manager to get a random question from any pack
    currentQuestion = questionManager.getNextQuestion();
    displayedChoices = currentQuestion!.getShuffledChoices();
    selectedAnswer = null;
    feedback = null;

    // Track when this question was loaded
    _questionLoadedAt = DateTime.now();

    // Reset state for new question
    uiDisabled = false;
    isRetryAttempt = false;
    previousIncorrectAnswer = null;
    _timeoutActive = false;

    responseTimer?.cancel();
    responseTimer = Timer(responseTimeout, _handleTimeout);

    // Mark initial load as complete if this is the first time
    if (_isInitialLoad) {
      _isInitialLoad = false;
    }

    // Log that question was loaded (helpful for debugging FCM triggers)
    String theQuestion =
        currentQuestion == null ? "[Null]" : currentQuestion!.prompt;
    if (isScheduled) {
      Logger().i(
          'QuizController: New question loaded via FCM trigger ($theQuestion)');
      NotificationManager().log('Question loaded from FCM notification');
    } else {
      Logger().i('QuizController: Initial question loaded ($theQuestion)');
    }

    onStateChanged();
  }

  void _handleTimeout() async {
    // Only handle timeout if it's not already being handled
    if (_timeoutActive) return;

    if (selectedAnswer == null) {
      _timeoutActive = true; // Mark timeout as active
      feedback = isRetryAttempt
          ? '⏰ You missed the second chance.'
          : '⏰ You missed the question.';
      uiDisabled = true; // Disable UI after timeout
      await _soundService.playTimeoutSound();
      onStateChanged();

      // Log the missed check-in
      await logCheckIn(
        result: isRetryAttempt ? 'missed_retry' : 'missed',
        questionPrompt: currentQuestion!.prompt,
      );

      // Update the check-in schedule after missed check-in
      await _updateScheduleAfterCheckIn();

      // Clear all badges and notifications on timeout
      await _clearAllNotifications();

      Future.delayed(Duration(seconds: 3), () {
        _timeoutActive = false;
        onStateChanged();
      });
    }
  }

  void selectAnswer(AnswerOption answer) {
    selectedAnswer = answer;
    feedback = null;
    onStateChanged();
  }

  Future<void> submitAnswer() async {
    if (selectedAnswer == null || uiDisabled)
      return; // Prevent double submission

    // Immediately disable UI to prevent double-taps
    uiDisabled = true;
    onStateChanged(); // Update UI immediately

    responseTimer?.cancel();

    // ALWAYS clear badges and notifications when submitting any answer
    await _clearAllNotifications();

    final isCorrect = selectedAnswer == currentQuestion!.correctAnswer;

    if (isCorrect) {
      // Correct answer case
      feedback = '✅ Correct!';
      // uiDisabled already set above

      // Play correct sound
      await _soundService.playCorrectSound();

      onStateChanged();

      await logCheckIn(
        result: 'correct',
        questionPrompt: currentQuestion!.prompt,
      );

      // Update the check-in schedule after successful check-in
      await _updateScheduleAfterCheckIn();
    } else {
      // Incorrect answer case
      if (!isRetryAttempt) {
        // First incorrect attempt - allow retry
        previousIncorrectAnswer = selectedAnswer;
        feedback = '❌ Incorrect. Try again.';
        selectedAnswer = null;
        isRetryAttempt = true;
        uiDisabled = false; // Re-enable UI for retry

        // Play first incorrect sound
        await _soundService.playIncorrectFirstSound();

        onStateChanged();

        // Log the first incorrect attempt
        await logCheckIn(
          result: 'incorrect_first_attempt',
          questionPrompt: currentQuestion!.prompt,
        );

        // Restart the timer for the second attempt
        responseTimer = Timer(responseTimeout, _handleTimeout);
      } else {
        // Second incorrect attempt - keep UI disabled
        feedback = '❌ Incorrect';
        // uiDisabled remains true

        // Play final incorrect sound
        await _soundService.playIncorrectFinalSound();

        onStateChanged();

        // Log the final incorrect result
        await logCheckIn(
          result: 'incorrect',
          questionPrompt: currentQuestion!.prompt,
        );

        // Update the check-in schedule after failed check-in
        await _updateScheduleAfterCheckIn();
      }
    }
  }

  /// Clear all badges and notifications
  Future<void> _clearAllNotifications() async {
    try {
      await NotificationManager().clearIOSBadge();
      await NotificationManager().cancelAllNotifications();
      Logger().i('QuizController: Cleared all badges and notifications');
    } catch (e) {
      Logger().e('QuizController: Error clearing notifications: $e');
    }
  }

  /// Update the check-in schedule after any check-in completion (success or failure)
  Future<void> _updateScheduleAfterCheckIn() async {
    try {
      await CheckInScheduler.updateAfterCheckIn();
      Logger().i('QuizController: Check-in schedule updated after completion');
    } catch (e) {
      Logger().i('QuizController: Error updating check-in schedule: $e');
      // Don't block the UI for scheduler errors
    }
  }

  Future<void> logCheckIn({
    required String result,
    required String questionPrompt,
  }) async {
    try {
      final now = DateTime.now();

      // Get the current user's UID from AuthService
      final uid = AuthService.currentUserId;

      Logger().i(
          "SAVE: Writing check-in data to responder_status/$uid/check_ins/${now.toIso8601String()}");
      Logger().i(
          "SAVE: Data: result=$result, prompt=$questionPrompt, timestamp=${now.toIso8601String()}");

      // First, ensure the parent document exists by creating it if needed
      final responderStatusRef =
          FirebaseFirestore.instance.collection('responder_status').doc(uid);

      // Get the document to check if it exists
      final docSnapshot = await responderStatusRef.get();

      // If parent document doesn't exist, create it with basic metadata
      if (!docSnapshot.exists) {
        await responderStatusRef.set({
          'createdAt': now.toIso8601String(),
          'userId': uid,
          'lastActivity': now.toIso8601String(),
        });
        Logger().i("SAVE: Created parent responder_status document");
      } else {
        // Update the lastActivity timestamp in the parent document
        await responderStatusRef.update({
          'lastActivity': now.toIso8601String(),
        });
        Logger().i("SAVE: Updated lastActivity in parent document");
      }

      // Now create the check-in document in the subcollection with a unique ID
      // Use timestamp as document ID for easy ordering
      final checkInRef =
          responderStatusRef.collection('check_ins').doc(now.toIso8601String());

      await checkInRef.set({
        'timestamp': now.toIso8601String(),
        'result': result,
        'prompt': questionPrompt,
        'responderId':
            currentRole.name, // Keep this for backward compatibility/filtering
      });

      Logger().i("SAVE: Successfully wrote check-in data!");
    } catch (e, stackTrace) {
      Logger().e("ERROR: Failed to log check-in: $e");
      Logger().i("Stack trace: $stackTrace");
    }
  }

  Map<String, Map<String, dynamic>> getPacksProgress() {
    return questionManager.getPacksProgress();
  }

  // Set up FCM message listener for proactive refresh
  void _setupFCMMessageListener() {
    // Listen for FCM messages when app is in foreground
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      Logger().i('QuizController: Received FCM message in foreground');
      NotificationManager()
          .log('QuizController: FCM message received: ${message.messageId}');

      // Extract message details
      final data = message.data;

      // Check if this is a check-in reminder
      if (data['type'] == 'check_in_reminder') {
        Logger().i('QuizController: Processing check-in reminder from FCM while in foreground');
        _refreshQuestionFromFCM();
      }
    });

    // Listen for when app is opened from FCM notification
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      Logger().i('QuizController: App opened from FCM notification');
      NotificationManager()
          .log('QuizController: App opened from FCM: ${message.messageId}');

      final data = message.data;

      // If opened from a check-in reminder, ensure we show a fresh question
      if (data['type'] == 'check_in_reminder') {
        _refreshQuestionFromFCM();
      }
    });

    Logger().i('QuizController: FCM message listeners set up');
  }

  // Helper method to refresh question when FCM triggers it
  void _refreshQuestionFromFCM() {
    Logger().i('QuizController: Refreshing question due to FCM trigger');
    _refreshQuestionWithFeedback('New check-in loaded');
  }

  // Unified method to refresh question with optional feedback
  Future<void> _refreshQuestionWithFeedback(String? feedbackMessage) async {
    // Cancel existing response timer
    responseTimer?.cancel();

    // Reset timeout state
    _timeoutActive = false;

    // Clear any existing notifications/badges
    await _clearAllNotifications();

    // Load a fresh question
    currentQuestion = questionManager.getNextQuestion();
    displayedChoices = currentQuestion!.getShuffledChoices();
    selectedAnswer = null;
    uiDisabled = false;
    isRetryAttempt = false;
    previousIncorrectAnswer = null;
    
    // Track when this question was loaded
    _questionLoadedAt = DateTime.now();
    
    // Show brief feedback if provided
    if (feedbackMessage != null) {
      feedback = feedbackMessage;
      // Clear feedback after a short delay
      Timer(Duration(seconds: 2), () {
        feedback = null;
        onStateChanged();
      });
    } else {
      feedback = null;
    }
    
    onStateChanged();

    // Set new timeout
    responseTimer = Timer(responseTimeout, _handleTimeout);

    Logger().i('QuizController: Question refreshed with feedback: $feedbackMessage');
  }
}