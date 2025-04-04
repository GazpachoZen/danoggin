// Copyright (c) 2025, Blue Vista Solutions.  All rights reserved.
//
// This source code is part of the Danoggin project and is intended for 
// internal or authorized use only. Unauthorized copying, modification, or 
// distribution of this file, via any medium, is strictly prohibited. For 
// licensing or permissions, contact: ivory@blue-vistas.com
//------------------------------------------------------------------------

import 'answer_option.dart';
import 'dart:math';

class Question {
  final String prompt;
  final AnswerOption correctAnswer;
  final List<AnswerOption> decoyAnswers;

  Question({
    required this.prompt,
    required this.correctAnswer,
    required this.decoyAnswers,
  });

  factory Question.fromJson(Map<String, dynamic> json) {
    return Question(
      prompt: json['prompt'] as String,
      correctAnswer: AnswerOption.fromJson(json['correctAnswer']),
      decoyAnswers: (json['decoyAnswers'] as List)
          .map((item) => AnswerOption.fromJson(item))
          .toList(),
    );
  }

  List<AnswerOption> getShuffledChoices() {
    final random = Random();
    final decoys = [...decoyAnswers]..shuffle(random);
    final selectedDecoys = decoys.take(3).toList();
    final allChoices = [...selectedDecoys, correctAnswer]..shuffle(random);
    return allChoices;
  }
}
