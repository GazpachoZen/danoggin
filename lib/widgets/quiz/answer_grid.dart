// Copyright (c) 2025, Blue Vista Solutions.  All rights reserved.
//
// This source code is part of the Danoggin project and is intended for
// internal or authorized use only. Unauthorized copying, modification, or
// distribution of this file, via any medium, is strictly prohibited. For
// licensing or permissions, contact: danoggin@blue-vistas.com
//------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:danoggin/models/answer_option.dart';
import 'package:danoggin/theme/app_colors.dart';

class AnswerGrid extends StatelessWidget {
  final List<AnswerOption> choices;
  final AnswerOption? selectedAnswer;
  final AnswerOption? previousIncorrectAnswer;
  final bool isDisabled;
  final Function(AnswerOption) onAnswerSelected;

  const AnswerGrid({
    Key? key,
    required this.choices,
    required this.selectedAnswer,
    this.previousIncorrectAnswer,
    this.isDisabled = false,
    required this.onAnswerSelected,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.0,
      children: choices.map((answer) {
        final isSelected = selectedAnswer == answer;
        final isPreviousIncorrect = answer == previousIncorrectAnswer;

        // Determine button disabled state
        final isButtonDisabled = isDisabled || isPreviousIncorrect;

        // Determine background color based on state
        Color backgroundColor;
        if (isDisabled) {
          // After answering, all buttons return to gray
          backgroundColor = AppColors.lightGray;
        } else if (isPreviousIncorrect) {
          // Incorrect answer from first attempt gets light pink
          backgroundColor = Colors.pink.shade100;
        } else if (isSelected) {
          // Selected answer uses coral from palette
          backgroundColor = AppColors.coral;
        } else {
          // Default state uses light gray
          backgroundColor = AppColors.lightGray;
        }

        return ElevatedButton(
          onPressed: isButtonDisabled ? null : () => onAnswerSelected(answer),
          style: ElevatedButton.styleFrom(
            backgroundColor: backgroundColor,
            padding: EdgeInsets.all(4),
            disabledBackgroundColor: isPreviousIncorrect && !isDisabled
                ? Colors.pink
                    .shade100 // Keep pink for previous incorrect during second attempt
                : Colors
                    .grey.shade300, // Gray for all buttons after final answer
          ),
          child: answer.render(disabled: isButtonDisabled),
        );
      }).toList(),
    );
  }
}
