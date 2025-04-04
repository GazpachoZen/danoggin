// Copyright (c) 2025, Blue Vista Solutions.  All rights reserved.
//
// This source code is part of the Danoggin project and is intended for 
// internal or authorized use only. Unauthorized copying, modification, or 
// distribution of this file, via any medium, is strictly prohibited. For 
// licensing or permissions, contact: ivory@blue-vistas.com
//------------------------------------------------------------------------

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
