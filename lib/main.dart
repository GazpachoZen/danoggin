
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/auth_service.dart';
import 'repositories/user_repository.dart';
import 'models/user_role.dart';
import 'screens/quiz_page.dart';
import 'screens/observer_page.dart';
import 'screens/role_selection_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  print('Starting Firebase init...');
  await Firebase.initializeApp();
  print('Firebase initialized.');

  print('Ensuring anonymous sign-in...');
  await AuthService.ensureSignedIn();
  print('User signed in: ${AuthService.currentUserId}');

  print('Checking role...');
  final uid = AuthService.currentUserId;
  final role = await UserRepository.getUserRole(uid);
  print('Role from Firestore: $role');

  runApp(MyApp(initialRole: role));
}

class MyApp extends StatelessWidget {
  final UserRole? initialRole;

  const MyApp({super.key, required this.initialRole});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Danoggin',
      theme: ThemeData(primarySwatch: Colors.deepPurple),
      home: initialRole == null
          ? RoleSelectionScreen()
          : (initialRole == UserRole.responder
              ? QuizPage()
              : ObserverPage()),
    );
  }
}
