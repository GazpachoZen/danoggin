
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:danoggin/models/question.dart';
import 'package:danoggin/models/answer_option.dart';
import 'package:danoggin/models/question_pack.dart';
import 'package:danoggin/models/user_role.dart';
import 'package:danoggin/services/notification_service.dart';
import 'package:danoggin/screens/settings_page.dart';

class QuizPage extends StatefulWidget {
  @override
  _QuizPageState createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  late QuestionPack pack;
  bool isLoading = true;

  late Question currentQuestion;
  List<AnswerOption> displayedChoices = [];

  AnswerOption? selectedAnswer;
  String? feedback;

  Timer? alertTimer;
  Timer? responseTimer;
  final Duration alertInterval = Duration(minutes: 5);
  final Duration responseTimeout = Duration(minutes: 1);

  late UserRole currentRole;

  @override
  void initState() {
    super.initState();
    loadPackFromFirestore();
  }

  Future<void> loadPackFromFirestore() async {
    try {
      final doc = await QuestionPack.loadFromFirestore('demo_pack');
      final prefs = await SharedPreferences.getInstance();
      final roleStr = prefs.getString('userRole');
      currentRole = UserRoleExtension.fromString(roleStr) ?? UserRole.responder;

      pack = doc;
      loadRandomQuestion();
      setState(() {
        isLoading = false;
      });
      startAlertLoop();
    } catch (e) {
      print('Error loading pack: \$e');
    }
  }

  void startAlertLoop() {
    alertTimer?.cancel();
    alertTimer = Timer.periodic(alertInterval, (_) => loadRandomQuestion());
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

  void _handleTimeout() {
    if (selectedAnswer == null) {
      setState(() {
        feedback = '⏰ You missed the question.';
      });
      // TODO: Record timeout to Firestore
    }
  }

  void submitAnswer() {
    if (selectedAnswer == null) return;

    responseTimer?.cancel();

    setState(() {
      feedback = (selectedAnswer == currentQuestion.correctAnswer)
          ? '✅ Correct!'
          : '❌ Incorrect';
    });

    // TODO: Record answer to Firestore
  }

  @override
  void dispose() {
    alertTimer?.cancel();
    responseTimer?.cancel();
    super.dispose();
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
        title: Text('Danoggin (${currentRole.name[0].toUpperCase()}${currentRole.name.substring(1)})'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () async {
              final newRole = await Navigator.push<UserRole>(
                context,
                MaterialPageRoute(builder: (context) => SettingsPage(currentRole: currentRole)),
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
