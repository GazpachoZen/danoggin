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

  final _notificationManager = NotificationManager();

  // Operational settings
  TimeOfDay? startHour;
  TimeOfDay? endHour;
  Duration alertInterval = Duration(minutes: 5);
  Duration responseTimeout = Duration(minutes: 1);

  // Timers
  Timer? alertTimer;
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
    _setupNotificationListener();

    // Load question packs and initialize
    await loadPackFromFirestore();
  }

  void dispose() {
    _notificationSubscription.cancel();
    alertTimer?.cancel();
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
      print('Error loading user name: $e');
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
      startAlertLoop();
    } catch (e) {
      print('Error loading packs: $e');
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

  bool _isWithinActiveHours() {
    if (startHour == null || endHour == null) return true;

    final now = TimeOfDay.now();
    final nowMinutes = now.hour * 60 + now.minute;
    final startMinutes = startHour!.hour * 60 + startHour!.minute;
    final endMinutes = endHour!.hour * 60 + endHour!.minute;

    return nowMinutes >= startMinutes && nowMinutes <= endMinutes;
  }

  // Methods for quiz operation
  void startAlertLoop() {
    alertTimer?.cancel();
    alertTimer = Timer.periodic(alertInterval, (_) async {
      final prefs = await SharedPreferences.getInstance();
      final startStr = prefs.getString('startHour') ?? '08:00';
      final endStr = prefs.getString('endHour') ?? '20:00';
      _parseOperationHours(startStr, endStr);

      if (_isWithinActiveHours()) {
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
    uiDisabled = false;
    isRetryAttempt = false;
    previousIncorrectAnswer = null;
    _timeoutActive = false; // Reset timeout flag for new question

    responseTimer?.cancel();
    responseTimer = Timer(responseTimeout, _handleTimeout);

    // Only show alert with refresh event if it's a scheduled update (not initial load)
    if (isScheduled || !_isInitialLoad) {
      // Use the NotificationHelper to show the check-in notification
      NotificationManager().useBestNotification(
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
      onStateChanged();

      // Log the missed check-in
      await logCheckIn(
        result: isRetryAttempt ? 'missed_retry' : 'missed',
        questionPrompt: currentQuestion!.prompt,
      );

      // Cancel any outstanding check-in notifications since we've now handled the timeout
      await NotificationManager().cancelNotification(1);

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

    // Cancel any outstanding check-in notifications to prevent confusion
    await NotificationManager().cancelNotification(1);

    final isCorrect = selectedAnswer == currentQuestion!.correctAnswer;

    if (isCorrect) {
      // Correct answer case
      feedback = '✅ Correct!';
      uiDisabled = true; // Disable UI after correct answer
      onStateChanged();

      await logCheckIn(
        result: 'correct',
        questionPrompt: currentQuestion!.prompt,
      );

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
        onStateChanged();

        // Log the final incorrect result
        await logCheckIn(
          result: 'incorrect',
          questionPrompt: currentQuestion!.prompt,
        );
      }
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

      print(
          "SAVE: Writing check-in data to responder_status/$uid/check_ins/${now.toIso8601String()}");
      print(
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
        print("SAVE: Created parent responder_status document");
      } else {
        // Update the lastActivity timestamp in the parent document
        await responderStatusRef.update({
          'lastActivity': now.toIso8601String(),
        });
        print("SAVE: Updated lastActivity in parent document");
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

      print("SAVE: Successfully wrote check-in data!");
    } catch (e, stackTrace) {
      print("ERROR: Failed to log check-in: $e");
      print("Stack trace: $stackTrace");
    }
  }

  Map<String, Map<String, dynamic>> getPacksProgress() {
    return questionManager.getPacksProgress();
  }

  // Add method to set up notification listener
  void _setupNotificationListener() {
    // Listen for notification events using a stream
    _notificationSubscription = _notificationManager.notificationEvents.listen((event) {
      // If app is already open and showing a question, refresh to the new question
      if (!isLoading && !_isInitialLoad) {
        print('Received notification event, refreshing question');

        // Cancel existing response timer
        responseTimer?.cancel();

        // Reset timeout state
        _timeoutActive = false;

        // Refresh the question without triggering another notification
        currentQuestion = questionManager.getNextQuestion();
        displayedChoices = currentQuestion!.getShuffledChoices();
        selectedAnswer = null;
        feedback = null;
        uiDisabled = false;
        isRetryAttempt = false;
        previousIncorrectAnswer = null;
        onStateChanged();

        // Set new timeout
        responseTimer?.cancel();
        responseTimer = Timer(responseTimeout, _handleTimeout);

        print('Question refreshed due to notification event');
      }
    });
  }
}
