import 'package:flutter/material.dart';
import 'screens/quiz_page.dart';

// Here's the obligatory main method, where everything starts...
void main() {
  runApp(MyApp());
}

// This is our top level class. In this example, it's a StatelessWidget, and we're overriding
// how it's built. Of course, we're still pretty trivial. The build method somehow is given
// context through Flutter magic, and we have no idea yet what's in it. Even so, all we really
// do is return something called a MaterialApp that has a title, a color theme, and a home page
// of some sort.
class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Quiz Demo',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: QuizPage(),
    );
  }
}