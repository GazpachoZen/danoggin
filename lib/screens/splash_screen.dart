import 'package:danoggin/services/notifications/notification_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:danoggin/services/auth_service.dart';
import 'package:danoggin/repositories/user_repository.dart';
import 'package:danoggin/repositories/responder_settings_repository.dart';
import 'package:danoggin/models/user_role.dart';
import 'package:danoggin/screens/quiz_page.dart';
import 'package:danoggin/screens/observer_page.dart';
import 'package:danoggin/screens/role_selection_screen.dart';
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

  // Add version info state variables
  String _version = "";
  String _buildNumber = "";

  @override
  void initState() {
    // Remove the native splash screen when your app is ready
    FlutterNativeSplash.remove();

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

    // Get version info then start the initialization process
    _getVersionInfo().then((_) {
      // Start the initialization process
      _initializeApp();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // New method to fetch version information
  Future<void> _getVersionInfo() async {
    try {
      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      setState(() {
        _version = packageInfo.version;
        _buildNumber = packageInfo.buildNumber;
      });
      print('App version: $_version+$_buildNumber');
    } catch (e) {
      print('❌ Error getting package info: $e');
      // If we can't get version info, just continue with empty values
    }
  }

  Future<void> _initializeApp() async {
    try {
      // Initialize notification system first
      setState(() => _statusMessage = "Setting up notifications...");
      try {
        // Just verify NotificationHelper is working, initialization happened in main.dart
        print('Notification system verification...');
      } catch (e) {
        print('❌ Error verifying notifications: $e');
        // Continue with app initialization even if notification verification fails
      }

      // Initialize time zone helper
      setState(() => _statusMessage = "Initializing time zones...");
      await TimezoneHelper.initialize();

      // Check if Firebase is initialized and ready
      setState(() => _statusMessage = "Checking services...");
      int attempts = 0;
      while (attempts < 10) {
        try {
          // Try to access Firebase
          if (Firebase.apps.isNotEmpty) {
            final app = Firebase.app();
            print('Firebase is initialized and working: ${app.name}');
            break; // Success - exit the loop
          }
        } catch (e) {
          // Ignore errors, just retry
          print('Attempt ${attempts + 1}: Firebase not ready yet');
        }

        // Wait a bit before trying again
        await Future.delayed(Duration(milliseconds: 200));
        attempts++;
      }

      if (attempts >= 10) {
        setState(() {
          _statusMessage = "Firebase initialization timed out";
          _error = true;
        });
        return;
      }

      print('Firebase verification complete');

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

      setState(() => _statusMessage = "Setting up notifications...");
      try {
        NotificationManager()
            .log('Starting FCM initialization during splash screen');
        await NotificationManager().initializeFCM();
        NotificationManager().log('FCM initialization completed during splash');
      } catch (e) {
        NotificationManager()
            .log('FCM initialization failed during splash: $e');
        // Continue anyway - don't block app launch for FCM issues
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
                  'assets/images/danoggin_icon.png',
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
                // Display version number if available
                if (_version.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      'v$_version (Build $_buildNumber)',
                      style: TextStyle(
                        color: AppColors.deepBlue.withOpacity(0.7),
                        fontSize: 14,
                      ),
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
                    valueColor:
                        AlwaysStoppedAnimation<Color>(AppColors.deepBlue),
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
