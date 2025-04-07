// Copyright (c) 2025, Blue Vista Solutions.  All rights reserved.
//
// This source code is part of the Danoggin project and is intended for 
// internal or authorized use only. Unauthorized copying, modification, or 
// distribution of this file, via any medium, is strictly prohibited. For 
// licensing or permissions, contact: ivory@blue-vistas.com
//------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'models/user_role.dart';
import 'screens/role_selection_screen.dart';
import 'screens/quiz_page.dart';
import 'screens/observer_page.dart';
import 'services/notification_service.dart';


// Here's the obligatory main method, where everything starts...

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.initialize();
  await Firebase.initializeApp();

  final role = await loadUserRole();

  runApp(MaterialApp(
    title: 'Danoggin',
    theme: ThemeData(primarySwatch: Colors.deepPurple),
    home: role == null
        ? RoleSelectionScreen()
        : (role == UserRole.responder
            ? QuizPage()
            : ObserverPage()),
  ));
}
