import 'package:cloud_firestore/cloud_firestore.dart';
import 'question.dart';
import 'dart:math';

class QuestionPack {
  final String id;
  final String name;
  final List<Question> questions;
  
  // Add these properties to track state
  late List<Question> _shuffledQuestions;
  int _currentIndex = 0;

  QuestionPack({
    required this.id,
    required this.name,
    required this.questions,
  }) {
    // Initialize shuffled questions
    resetSequence();
  }

  // This maintains backward compatibility
  Question getRandomQuestion() {
    return getNextQuestion();
  }
  
  // New method to get next question in sequence
  Question getNextQuestion() {
    // If we've used all questions, reshuffle
    if (_currentIndex >= _shuffledQuestions.length) {
      _shuffledQuestions.shuffle();
      _currentIndex = 0;
    }
    
    // Get question and increment index
    return _shuffledQuestions[_currentIndex++];
  }
  
  // Method to reset the sequence if needed
  void resetSequence() {
    _shuffledQuestions = List.from(questions);
    _shuffledQuestions.shuffle();
    _currentIndex = 0;
  }

  factory QuestionPack.fromJson(String docId, Map<String, dynamic> json) {
    return QuestionPack(
      id: docId,
      name: json['name'] as String,
      questions: (json['questions'] as List)
          .map((item) => Question.fromJson(item))
          .toList(),
    );
  }

  static Future<QuestionPack> loadFromFirestore(String packId) async {
    final doc = await FirebaseFirestore.instance
        .collection('question_packs')
        .doc(packId)
        .get();

    final data = doc.data();
    if (data == null) {
      throw Exception('No data found for pack \$packId');
    }

    return QuestionPack.fromJson(doc.id, data);
  }
}