// Modified version: question_manager.dart
import 'dart:math';
import 'package:danoggin/models/question.dart';
import 'package:danoggin/models/question_pack.dart';

class QuestionManager {
  final List<QuestionPack> questionPacks;
  final Random _random = Random();
  
  // Track our own progress information
  final Map<String, int> _packProgress = {};
  
  QuestionManager(this.questionPacks) {
    // Ensure all packs are initialized with shuffled questions
    for (final pack in questionPacks) {
      pack.resetSequence();
      // Initialize progress tracking
      _packProgress[pack.id] = 0;
    }
  }
  
  // Get a random question from any of the subscribed packs
  Question getNextQuestion() {
    if (questionPacks.isEmpty) {
      throw Exception('No question packs available');
    }
    
    // Select a random pack
    final selectedPack = questionPacks[_random.nextInt(questionPacks.length)];
    
    // Get the next question from that pack
    final question = selectedPack.getNextQuestion();
    
    // Update our progress tracking
    _packProgress[selectedPack.id] = (_packProgress[selectedPack.id] ?? 0) + 1;
    
    // If we've gone through all questions, reset our counter
    if (_packProgress[selectedPack.id]! >= selectedPack.questions.length) {
      _packProgress[selectedPack.id] = 0;
    }
    
    return question;
  }
  
  // Get information about all packs
  Map<String, Map<String, dynamic>> getPacksProgress() {
    final result = <String, Map<String, dynamic>>{};
    
    for (final pack in questionPacks) {
      result[pack.id] = {
        'name': pack.name,
        'total': pack.questions.length,
        'completed': _packProgress[pack.id] ?? 0,
      };
    }
    
    return result;
  }
}