import 'package:flutter/material.dart';
import '../models/question.dart';
import '../models/answer_option.dart';
import '../models/question_pack.dart';

// This is previously mentioned home page. In this example, it's a StatefulWidget... not sure if
// that's required, or if we could use something else. Notice that all we really do is override and
// provide our own createState method. That, in turn, is a class that does all the real work.
class QuizPage extends StatefulWidget {
  @override
  _QuizPageState createState() => _QuizPageState();
}

// Finally, we can get down to making things.
// This class is where the interesting stuff happens.
class _QuizPageState extends State<QuizPage> {
  late QuestionPack pack;
  int currentQuestionIndex = 0;

  late Question currentQuestion;
  List<AnswerOption> displayedChoices = [];

  AnswerOption? selectedAnswer;
  String? feedback;

  @override
  void initState() {
    super.initState();

    pack = QuestionPack(
      id: 'basic-1',
      name: 'Basic Demo Pack',
      questions: [
        Question(
          prompt: 'Which is a fruit?',
          correctAnswer: AnswerOption(text: 'Apple'),
          decoyAnswers: [
            AnswerOption(text: 'Lamp'),
            AnswerOption(text: 'Desk'),
            AnswerOption(text: 'Shark'),
            AnswerOption(text: 'Book'),
          ],
        ),
        Question(
          prompt: 'Tap the dog',
          correctAnswer: AnswerOption(imagePath: 'assets/images/dog.png', text:'Pick me!'),
          decoyAnswers: [
            AnswerOption(imagePath: 'assets/images/cat.png', text:'Meow'),
            AnswerOption(imagePath: 'assets/images/elephant.png'),
            AnswerOption(imagePath: 'assets/images/rabbit.png'),
            AnswerOption(imagePath: 'assets/images/cow.png', text: 'Moo'),
          ],
        ),
        Question(
          prompt: 'Which is a vehicle?',
          correctAnswer: AnswerOption(text: 'Car'),
          decoyAnswers: [
            AnswerOption(text: 'Banana'),
            AnswerOption(text: 'Spoon'),
            AnswerOption(text: 'Jacket'),
            AnswerOption(text: 'Pillow'),
          ],
        ),
      ],
    );

    loadQuestion(0);
  }

  void loadQuestion(int index) {
    currentQuestion = pack.questions[index];
    displayedChoices = currentQuestion.getShuffledChoices();
    selectedAnswer = null;
    feedback = null;
  }

  void submitAnswer() {
    if (selectedAnswer == null) return;

    setState(() {
      feedback = (selectedAnswer == currentQuestion.correctAnswer)
          ? 'Correct!'
          : 'Try again';
    });
  }

  @override
  Widget build(BuildContext context) {
    // Question text
    Widget questionText = Text(
      currentQuestion.prompt,
      style: TextStyle(fontSize: 24),
    );

    // Grid of answer buttons (2x2 layout)
    Widget answerGrid = GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.8,
      children: displayedChoices.map((answer) {
        bool isSelected = selectedAnswer == answer;

        return ElevatedButton(
          onPressed: () {
            setState(() {
              selectedAnswer = answer;
              feedback = null;
            });
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: isSelected ? Colors.blueAccent : null,
            padding: EdgeInsets.all(12),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Center(
                child: answer.render(),
              );
            },
          ),
        );
      }).toList(),
    );

    // Submit button
    Widget submitButton = ElevatedButton(
      onPressed: selectedAnswer == null ? null : submitAnswer,
      child: Text('Submit'),
    );

    Widget nextButton = ElevatedButton(
      onPressed: (currentQuestionIndex < pack.questions.length - 1)
          ? () {
              setState(() {
                currentQuestionIndex++;
                loadQuestion(currentQuestionIndex);
              });
            }
          : null,
      child: Text('Next Question'),
    );

    // Feedback text
    Widget? feedbackText;
    if (feedback != null) {
      feedbackText = Text(
        feedback!,
        style: TextStyle(
          fontSize: 20,
          color: feedback == 'Correct!' ? Colors.green : Colors.red,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text('Simple Quiz')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            questionText,
            SizedBox(height: 24),
            answerGrid,
            SizedBox(height: 16),
            submitButton,
            SizedBox(height: 24),
            if (feedbackText != null) feedbackText,
            SizedBox(height: 12),
            nextButton,
          ],
        ),
      ),
    );
  }
}
