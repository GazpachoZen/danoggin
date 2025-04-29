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
        final isAnswerDisabled = isDisabled || isPreviousIncorrect;

        return ElevatedButton(
          onPressed: isAnswerDisabled
              ? null
              : () => onAnswerSelected(answer),
          style: ElevatedButton.styleFrom(
            backgroundColor: isSelected ? AppColors.coral : AppColors.lightGray,
            padding: EdgeInsets.all(4),
            disabledBackgroundColor: isPreviousIncorrect
                ? Colors.red.withOpacity(0.3)
                : null,
          ),
          child: answer.render(disabled: isAnswerDisabled),
        );
      }).toList(),
    );
  }
}