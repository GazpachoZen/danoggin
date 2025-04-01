import 'dart:math';
import 'answer_option.dart';

class Question {
  final String prompt;
  final AnswerOption correctAnswer;
  final List<AnswerOption> decoyAnswers;

  Question({
    required this.prompt,
    required this.correctAnswer,
    required this.decoyAnswers,
  });

  List<AnswerOption> getShuffledChoices() {
    final random = Random();
    final decoys = [...decoyAnswers]..shuffle(random);
    final selectedDecoys = decoys.take(3).toList();
    final allChoices = [...selectedDecoys, correctAnswer]..shuffle(random);
    return allChoices;
  }
}
