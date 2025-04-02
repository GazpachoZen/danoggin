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

  factory QuestionPack.fromJson(String docId, Map<String, dynamic> json) {
    return QuestionPack(
      id: docId,
      name: json['name'] as String,
      questions: (json['questions'] as List)
          .map((item) => Question.fromJson(item))
          .toList(),
    );
  }
}
