import 'package:flutter/material.dart';

class AnswerOption {
  final String? text;
  final String? imagePath;

  const AnswerOption({this.text, this.imagePath});

  Widget render() {
    List<Widget> content = [];

    if (imagePath != null) {
      content.add(Image.asset(
        imagePath!,
        height: 60,
        fit: BoxFit.contain,
      ));
    }

    if (text != null) {
      content.add(Text(
        text!,
        style: TextStyle(fontSize: 16),
        textAlign: TextAlign.center,
        softWrap: true,
        maxLines: 2,
      ));
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: content,
    );
  }

  @override
  String toString() => text ?? '[Image Answer]';
}
