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

class QuizPage extends StatefulWidget {
  @override
  _QuizPageState createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> with WidgetsBindingObserver {
  late QuestionPack pack;
  bool isLoading = true;
  TimeOfDay? startHour;
  TimeOfDay? endHour;
  late Question currentQuestion;
  List<AnswerOption> displayedChoices = [];

  AnswerOption? selectedAnswer;
  String? feedback;

  Timer? alertTimer;
  Timer? responseTimer;

  // Will be set based on settings
  Duration alertInterval = Duration(minutes: 5);
  Duration responseTimeout = Duration(minutes: 1);

  late UserRole currentRole;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    loadPackFromFirestore();
  }

  @override
  void dispose() {
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
      final doc = await QuestionPack.loadFromFirestore('demo_pack');
      final prefs = await SharedPreferences.getInstance();
      final roleStr = prefs.getString('userRole');
      currentRole = UserRoleExtension.fromString(roleStr) ?? UserRole.responder;

      pack = doc;

      final startStr = prefs.getString('startHour') ?? '08:00';
      final endStr = prefs.getString('endHour') ?? '20:00';
      _parseOperationHours(startStr, endStr);
      final frequency = prefs.getDouble('alertFrequency') ?? 180;
      final timeout = prefs.getDouble('timeoutDuration') ?? 1;

      alertInterval = Duration(minutes: frequency.round());
      responseTimeout = Duration(minutes: timeout.round());

      loadRandomQuestion();
      setState(() {
        isLoading = false;
      });
      startAlertLoop();
    } catch (e) {
      print('Error loading pack: $e');
    }
  }

  void startAlertLoop() {
    alertTimer?.cancel();
    alertTimer = Timer.periodic(alertInterval, (_) {
      if (_isWithinActiveHours()) {
        loadRandomQuestion();
      }
    });
  }

  void loadRandomQuestion() {
    currentQuestion = pack.getRandomQuestion();
    displayedChoices = currentQuestion.getShuffledChoices();
    selectedAnswer = null;
    feedback = null;

    responseTimer?.cancel();
    responseTimer = Timer(responseTimeout, _handleTimeout);

    NotificationService.showBasicNotification(
      id: 1,
      title: 'Danoggin Check-In',
      body: 'Time to answer a quick question!',
    );
  }

  void _handleTimeout() async {
    if (selectedAnswer == null) {
      setState(() {
        feedback = '⏰ You missed the question.';
      });
      await logCheckIn(
        responderId: currentRole.name,
        result: 'missed',
        questionPrompt: currentQuestion.prompt,
      );
    }
  }

  Future<void> submitAnswer() async {
    if (selectedAnswer == null) return;

    responseTimer?.cancel();

    final isCorrect = selectedAnswer == currentQuestion.correctAnswer;

    setState(() {
      feedback = isCorrect ? '✅ Correct!' : '❌ Incorrect';
    });

    await logCheckIn(
      responderId: currentRole.name,
      result: isCorrect ? 'correct' : 'incorrect',
      questionPrompt: currentQuestion.prompt,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text('Loading...')),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
            'Danoggin (${currentRole.name[0].toUpperCase()}${currentRole.name.substring(1)})'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () async {
              final newRole = await Navigator.push<UserRole>(
                context,
                MaterialPageRoute(
                    builder: (context) =>
                        SettingsPage(currentRole: currentRole)),
              );
              if (newRole != null && newRole != currentRole) {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('userRole', newRole.name);
                setState(() {
                  currentRole = newRole;
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
            Text(currentQuestion.prompt, style: TextStyle(fontSize: 24)),
            SizedBox(height: 24),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.0,
              children: displayedChoices.map((answer) {
                final isSelected = selectedAnswer == answer;
                return ElevatedButton(
                  onPressed: () {
                    setState(() {
                      selectedAnswer = answer;
                      feedback = null;
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isSelected ? Colors.blueAccent : null,
                    padding: EdgeInsets.all(4),
                  ),
                  child: answer.render(),
                );
              }).toList(),
            ),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: selectedAnswer == null ? null : submitAnswer,
              child: Text('Submit'),
            ),
            SizedBox(height: 24),
            if (feedback != null)
              Text(
                feedback!,
                style: TextStyle(
                  fontSize: 20,
                  color: feedback == '✅ Correct!' ? Colors.green : Colors.red,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Future<void> logCheckIn({
  required String responderId,
  required String result,
  required String questionPrompt,
}) async {
  final now = DateTime.now();
  final doc = FirebaseFirestore.instance
      .collection('responder_status')
      .doc(responderId)
      .collection('check_ins')
      .doc(now.toIso8601String());

  await doc.set({
    'timestamp': now.toIso8601String(),
    'result': result,
    'prompt': questionPrompt,
  });
}
