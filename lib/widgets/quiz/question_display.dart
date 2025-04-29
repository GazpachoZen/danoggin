import 'package:flutter/material.dart';
import 'package:danoggin/models/question.dart';

class QuestionDisplay extends StatelessWidget {
  final Question question;
  
  const QuestionDisplay({
    Key? key,
    required this.question,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Text(
      question.prompt, 
      style: TextStyle(fontSize: 24)
    );
  }
}