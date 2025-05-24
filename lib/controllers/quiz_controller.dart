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
    if (isScheduled) {
      Logger().i('QuizController: New question loaded via FCM trigger');
      NotificationManager().log('Question loaded from FCM notification');
    } else {
      Logger().i('QuizController: Initial question loaded');
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

      // Cancel any outstanding check-in notifications since we've now handled the timeout
      await NotificationManager().clearIOSBadge();

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
    if (selectedAnswer == null) return;

    responseTimer?.cancel();

    // Clear all badges when answering any question
    await NotificationManager().clearIOSBadge();

    final isCorrect = selectedAnswer == currentQuestion!.correctAnswer;

    if (isCorrect) {
      // Correct answer case
      feedback = '✅ Correct!';
      uiDisabled = true; // Disable UI after correct answer

      // Play correct sound
      await _soundService.playCorrectSound();

      onStateChanged();

      await logCheckIn(
        result: 'correct',
        questionPrompt: currentQuestion!.prompt,
      );

      // Update the check-in schedule after successful check-in
      await _updateScheduleAfterCheckIn();

      // Also cancel any missed check-in notifications on successful answer
      await NotificationManager().cancelNotification(2);
    } else {
      // Incorrect answer case
      if (!isRetryAttempt) {
        // First incorrect attempt - allow retry
        previousIncorrectAnswer = selectedAnswer;
        feedback = '❌ Incorrect. Try again.';
        selectedAnswer = null;
        isRetryAttempt = true;

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
        // Second incorrect attempt - disable UI
        feedback = '❌ Incorrect';
        uiDisabled = true;

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

// Add method to set up FCM message listener instead of notification listener
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
        Logger().i('QuizController: Processing check-in reminder from FCM');

        // If app is already showing a question, refresh to new question
        if (!isLoading && !_isInitialLoad) {
          _refreshQuestionFromFCM();
        }
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

    // Cancel existing response timer
    responseTimer?.cancel();

    // Reset timeout state
    _timeoutActive = false;

    // Load a fresh question without generating local notification
    currentQuestion = questionManager.getNextQuestion();
    displayedChoices = currentQuestion!.getShuffledChoices();
    selectedAnswer = null;
    feedback = null;
    uiDisabled = false;
    isRetryAttempt = false;
    previousIncorrectAnswer = null;
    onStateChanged();

    // Set new timeout
    responseTimer = Timer(responseTimeout, _handleTimeout);

    Logger().i('QuizController: Question refreshed due to FCM');
  }
}
