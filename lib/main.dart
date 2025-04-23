import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/auth_service.dart';
import 'repositories/user_repository.dart';
import 'models/user_role.dart';
import 'screens/quiz_page.dart';
import 'screens/observer_page.dart';
import 'screens/role_selection_screen.dart';
import 'screens/splash_screen.dart';
import 'services/notification_service.dart';
import 'services/notification_helper.dart';
import 'theme/app_theme.dart';  // Import your theme

void main() async {
  // Ensure Flutter binding is initialized
  WidgetsFlutterBinding.ensureInitialized();
  
  // Run the app with splash screen
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Danoggin',
      theme: AppTheme.lightTheme,
      home: SplashScreen(),
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
    // Skip for splash screen
    if (!_permissionCheckDone && 
        route.settings.name == null && 
        !(route.settings.arguments is SplashScreen)) {
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