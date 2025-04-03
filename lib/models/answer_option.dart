import 'package:flutter/material.dart';

class AnswerOption {
  final String? text;
  final String? imagePath;

  const AnswerOption({this.text, this.imagePath});

  factory AnswerOption.fromJson(Map<String, dynamic> json) {
    return AnswerOption(
      text: json['text'] as String?,
      imagePath: json['imagePath'] as String?,
    );
  }

Widget render() {
  return LayoutBuilder(
    builder: (context, constraints) {
      final hasImage = imagePath != null;
      final hasText = text != null;

      // max size inside square button
      final maxSize = constraints.maxHeight;

      // Image height is flexible: large if solo, smaller if paired with text
      final imageHeight = hasText ? maxSize * 0.45 : maxSize * 0.75;

      // Text size is flexible: larger if solo, smaller if with image
      final fontSize = hasImage ? 16.0 : 22.0;

      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (hasImage)
            Container(
              height: imageHeight,
              child: Image.asset(
                imagePath!,
                fit: BoxFit.contain,
              ),
            ),
          if (hasText)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                text!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: fontSize),
                maxLines: 2,
                softWrap: true,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      );
    },
  );
}


  @override
  String toString() => text ?? '[Image Answer]';
}
