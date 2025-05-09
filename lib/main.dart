// Copyright (c) 2025, Blue Vista Solutions.  All rights reserved.
//
// This source code is part of the Danoggin project and is intended for
// internal or authorized use only. Unauthorized copying, modification, or
// distribution of this file, via any medium, is strictly prohibited. For
// licensing or permissions, contact: danoggin@blue-vistas.com
//------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'screens/splash_screen.dart';
import 'services/notification_helper.dart';
import 'theme/app_theme.dart';

void main() async {
  // Ensure Flutter binding is initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize notifications early but don't show dialogs yet
  try {
    await NotificationHelper.initialize();
    print('Notification system initialized in main()');
  } catch (e) {
    print('Error initializing notifications in main(): $e');
    // Continue even if notification initialization fails
  }

  // Run the app with splash screen
  runApp(AppLifecycleHandler(
    child: const MyApp(),
  ));
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
      Future.delayed(Duration(seconds: 2), () async {
        if (navigator?.context != null) {
          print('Checking notification permissions after app loaded');
          await NotificationHelper.showPermissionDialog(navigator!.context);
        }
      });
    }
  }
}

// App lifecycle handler to clean up resources
class AppLifecycleHandler extends StatefulWidget {
  final Widget child;

  const AppLifecycleHandler({Key? key, required this.child}) : super(key: key);

  @override
  _AppLifecycleHandlerState createState() => _AppLifecycleHandlerState();
}

class _AppLifecycleHandlerState extends State<AppLifecycleHandler>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Clean up resources
    NotificationHelper.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
