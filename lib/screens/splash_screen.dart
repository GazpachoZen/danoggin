import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:danoggin/services/auth_service.dart';
import 'package:danoggin/repositories/user_repository.dart';
import 'package:danoggin/repositories/responder_settings_repository.dart';
import 'package:danoggin/models/user_role.dart';
import 'package:danoggin/screens/quiz_page.dart';
import 'package:danoggin/screens/observer_page.dart';
import 'package:danoggin/screens/role_selection_screen.dart';
import 'package:danoggin/services/notification_helper.dart';
import 'package:danoggin/theme/app_colors.dart';
import 'package:danoggin/utils/timezone_helper.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeInAnimation;
  String _statusMessage = "Initializing...";
  bool _error = false;

  @override
  void initState() {
    super.initState();

    // Setup animation
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );

    _fadeInAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeIn,
      ),
    );

    _controller.forward();

    // Start the initialization process
    _initializeApp();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

Future<void> _initializeApp() async {
    try {
      // Initialize notification system first
      setState(() => _statusMessage = "Setting up notifications...");
      await NotificationHelper.initialize();

      // Initialize time zone helper
      setState(() => _statusMessage = "Initializing time zones...");
      await TimezoneHelper.initialize();

      // Initialize Firebase
      setState(() => _statusMessage = "Connecting to services...");
      print('Starting Firebase init...');
      await Firebase.initializeApp();
      print('Firebase initialized.');

      // Ensure user is signed in
      setState(() => _statusMessage = "Setting up your account...");
      print('Ensuring anonymous sign-in...');
      await AuthService.ensureSignedIn();
      print('User signed in: ${AuthService.currentUserId}');

      // Check user role
      setState(() => _statusMessage = "Loading your profile...");
      print('Checking role...');
      final uid = AuthService.currentUserId;
      final role = await UserRepository.getUserRole(uid);
      print('Role from Firestore: $role');
      
      // Sync settings to Firestore if needed
      if (role == UserRole.responder) {
        setState(() => _statusMessage = "Syncing your settings...");
        await ResponderSettingsRepository.syncLocalSettingsToFirestore(uid);
      }

      // Small delay to allow animation to complete
      await Future.delayed(const Duration(milliseconds: 800));

      // Navigate to the appropriate screen
      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => role == null
              ? RoleSelectionScreen()
              : (role == UserRole.responder
                  ? QuizPage(currentRole: role)
                  : ObserverPage()),
        ),
      );
    } catch (e) {
      print("Error during initialization: $e");
      setState(() {
        _statusMessage = "Failed to initialize: $e";
        _error = true;
      });
    }
  }

// In splash_screen.dart
@override
Widget build(BuildContext context) {
  return Scaffold(
    // Use the skyBlue color for the background
    backgroundColor: AppColors.skyBlue,
    body: SafeArea(
      child: Center(
        child: FadeTransition(
          opacity: _fadeInAnimation,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/images/danoggin_512x512.png',
                width: 200,
                height: 200,
              ),
              const SizedBox(height: 40),
              // App name with the deep blue color
              Text(
                'Danoggin',
                style: TextStyle(
                  color: AppColors.deepBlue,
                  fontSize: 42,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 40),
              // Status message with deep blue
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Text(
                  _statusMessage,
                  style: TextStyle(
                    color: AppColors.deepBlue.withOpacity(0.9),
                    fontSize: 16,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 24),
              if (!_error)
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.deepBlue),
                )
              else
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _error = false;
                      _statusMessage = "Retrying...";
                    });
                    _initializeApp();
                  },
                  child: const Text('Retry'),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

}
