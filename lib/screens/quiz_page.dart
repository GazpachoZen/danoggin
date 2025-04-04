// Copyright (c) 2025, Blue Vista Solutions.  All rights reserved.
//
// This source code is part of the Danoggin project and is intended for 
// internal or authorized use only. Unauthorized copying, modification, or 
// distribution of this file, via any medium, is strictly prohibited. For 
// licensing or permissions, contact: ivory@blue-vistas.com
//------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/question.dart';
import '../models/answer_option.dart';
import '../models/question_pack.dart';

// This is previously mentioned home page. In this example, it's a StatefulWidget... not sure if
// that's required, or if we could use something else. Notice that all we really do is override and
// provide our own createState method. That, in turn, is a class that does all the real work.
class QuizPage extends StatefulWidget {
  @override
  _QuizPageState createState() => _QuizPageState();
}

// Finally, we can get down to making things.
// This class is where the interesting stuff happens.
class _QuizPageState extends State<QuizPage> {
  late QuestionPack pack;
  int currentQuestionIndex = 0;
  bool isLoading = true;

  late Question currentQuestion;
  List<AnswerOption> displayedChoices = [];

  AnswerOption? selectedAnswer;
  String? feedback;

  @override
  void initState() {
    super.initState();
    loadPackFromFirestore();
  }

  Future<void> loadPackFromFirestore() async {
    print("At the top of loadPackFromFirestore...");
    try {
      print("Top of try...");
      final doc = await FirebaseFirestore.instance
          .collection('question_packs')
          .doc('demo_pack')
          .get();
      print("After awaiting...");
      if (doc.exists) {
        pack = QuestionPack.fromJson(doc.id, doc.data()!);
        loadQuestion(0);
        setState(() {
          isLoading = false;
        });
      } else {
        print('Pack not found');
      }
    } catch (e) {
      print('Error loading pack: $e');
    }
  }

  void loadQuestion(int index) {
    currentQuestion = pack.questions[index];
    displayedChoices = currentQuestion.getShuffledChoices();
    selectedAnswer = null;
    feedback = null;
  }

  void submitAnswer() {
    if (selectedAnswer == null) return;

    setState(() {
      feedback = (selectedAnswer == currentQuestion.correctAnswer)
          ? 'Correct!'
          : 'Try again';
    });
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      print("Showing the loading screen");
      return Scaffold(
        appBar: AppBar(title: Text('Loading...')),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Question text
    Widget questionText = Text(
      currentQuestion.prompt,
      style: TextStyle(fontSize: 24),
    );

    // Grid of answer buttons (2x2 layout)
Widget answerGrid = GridView.count(
  crossAxisCount: 2,
  shrinkWrap: true,
  crossAxisSpacing: 12,
  mainAxisSpacing: 12,
  childAspectRatio: 1.0, // 1:1 aspect ratio
  children: displayedChoices.map((answer) {
    bool isSelected = selectedAnswer == answer;

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
);

    // Submit button
    Widget submitButton = ElevatedButton(
      onPressed: selectedAnswer == null ? null : submitAnswer,
      child: Text('Submit'),
    );

    Widget nextButton = ElevatedButton(
      onPressed: (currentQuestionIndex < pack.questions.length - 1)
          ? () {
              setState(() {
                currentQuestionIndex++;
                loadQuestion(currentQuestionIndex);
              });
            }
          : null,
      child: Text('Next Question'),
    );

    // Feedback text
    Widget? feedbackText;
    if (feedback != null) {
      feedbackText = Text(
        feedback!,
        style: TextStyle(
          fontSize: 20,
          color: feedback == 'Correct!' ? Colors.green : Colors.red,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text('Simple Quiz')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            questionText,
            SizedBox(height: 24),
            answerGrid,
            SizedBox(height: 16),
            submitButton,
            SizedBox(height: 24),
            if (feedbackText != null) feedbackText,
            SizedBox(height: 12),
            nextButton,
          ],
        ),
      ),
    );
  }
}
