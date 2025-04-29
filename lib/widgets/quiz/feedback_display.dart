import 'package:flutter/material.dart';

class FeedbackDisplay extends StatelessWidget {
  final String? feedback;
  
  const FeedbackDisplay({
    Key? key,
    this.feedback,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    if (feedback == null) {
      return SizedBox.shrink();
    }
    
    Color textColor;
    if (feedback == '✅ Correct!') {
      textColor = Colors.green;
    } else if (feedback == '❌ Incorrect. Try again.') {
      textColor = Colors.orange;
    } else {
      textColor = Colors.red;
    }
    
    return Text(
      feedback!,
      style: TextStyle(
        fontSize: 20,
        color: textColor,
      ),
    );
  }
}