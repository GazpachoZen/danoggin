import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/auth_service.dart';
import 'repositories/user_repository.dart';
import 'models/user_role.dart';
import 'screens/quiz_page.dart';
import 'screens/observer_page.dart';
import 'screens/role_selection_screen.dart';
import 'services/notification_service.dart';
import 'services/notification_helper.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize notification system first
  await NotificationHelper.initialize();
  
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
      // Add this to check permissions after the app loads
      navigatorObservers: [
        _NotificationPermissionObserver(),
      ],
    );
  }
}

// Create a navigator observer to check permissions after initial page load
class _NotificationPermissionObserver extends NavigatorObserver {
  bool _permissionCheckDone = false;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    
    // Only check permissions once, after initial screen loads
    if (!_permissionCheckDone && route.settings.name == null) {
      _permissionCheckDone = true;
      
      // Delay slightly to ensure UI is fully loaded
      Future.delayed(Duration(seconds: 1), () async {
        if (navigator?.context != null) {
          await NotificationHelper.showPermissionDialog(navigator!.context);
        }
      });
    }
  }
}

// Register cleanup handler for app termination
void _cleanupResources() {
  // Clean up the notification stream controller
  NotificationHelper.dispose();
}