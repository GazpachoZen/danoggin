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
import 'package:firebase_core/firebase_core.dart';
import '../firebase_options.dart';
import 'dart:io';

void main() async {
  // Ensure Flutter binding is initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Start Firebase initialization but don't await it yet
  final firebaseInitialization = Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Start notification initialization but don't await it yet
  final notificationInitialization = NotificationHelper.initialize();

  // Run the app immediately without waiting for initializations to complete
  runApp(AppLifecycleHandler(
    child: const MyApp(),
  ));

  // Now await the initializations in the background
  try {
    await firebaseInitialization;
    print('Firebase initialized successfully in main()!');
  } catch (e) {
    print('Error initializing Firebase in main(): $e');
  }

  try {
    await notificationInitialization;
    print('Notification system initialized in main()');
  } catch (e) {
    print('Error initializing notifications in main(): $e');
  }
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
  // Add this static boolean to track active instances
  static bool _hasActiveInstance = false;
  
  // Add a new variable to track if we're in a resumed state
  bool _isResumed = false;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Add this method call to check for multiple instances
    _checkForMultipleInstances();
  }

  // Modified to prevent false detection when resuming
  void _checkForMultipleInstances() {
    if (_hasActiveInstance && !_isResumed) {
      print('WARNING: Multiple instances of Danoggin detected!');
      // Force exit this instance after a short delay to ensure message is logged
      Future.delayed(Duration(milliseconds: 100), () {
        exit(0); // This will terminate the current instance
      });
    } else {
      _hasActiveInstance = true;
      print('Danoggin instance initialized and active');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hasActiveInstance = false; // Mark this instance as disposed
    // Clean up resources
    NotificationHelper.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    if (state == AppLifecycleState.resumed) {
      // App came to foreground
      _isResumed = true;
      print('App resumed - checking for multiple instances');
      _checkForMultipleInstances();
    } else if (state == AppLifecycleState.detached) {
      // App is being terminated
      _hasActiveInstance = false;
      _isResumed = false;
      print('Danoggin instance terminated');
    } else if (state == AppLifecycleState.inactive || 
              state == AppLifecycleState.paused) {
      // App is in background or inactive
      _isResumed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
