import 'question.dart';

class QuestionPack {
  final String id;
  final String name;
  final List<Question> questions;

  QuestionPack({
    required this.id,
    required this.name,
    required this.questions,
  });
}
