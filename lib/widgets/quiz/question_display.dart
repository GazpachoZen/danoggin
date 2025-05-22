// Copyright (c) 2025, Blue Vista Solutions.  All rights reserved.
//
// This source code is part of the Danoggin project and is intended for
// internal or authorized use only. Unauthorized copying, modification, or
// distribution of this file, via any medium, is strictly prohibited. For
// licensing or permissions, contact: danoggin@blue-vistas.com
//------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:danoggin/models/question.dart';

class QuestionDisplay extends StatelessWidget {
  final Question question;
  final bool isDisabled;

  const QuestionDisplay({
    Key? key,
    required this.question,
    this.isDisabled = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Text(
      question.prompt, 
      style: TextStyle(
        fontSize: 24,
        color: isDisabled ? Colors.grey[600] : Colors.black87,
      ),
    );
  }
}