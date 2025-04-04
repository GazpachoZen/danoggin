// Copyright (c) 2025, Blue Vista Solutions.  All rights reserved.
//
// This source code is part of the Danoggin project and is intended for 
// internal or authorized use only. Unauthorized copying, modification, or 
// distribution of this file, via any medium, is strictly prohibited. For 
// licensing or permissions, contact: ivory@blue-vistas.com
//------------------------------------------------------------------------

import 'package:flutter/material.dart';
import '../models/user_role.dart';
import 'quiz_page.dart';
import 'observer_home_page.dart';

class RoleSelectionScreen extends StatelessWidget {
  void selectRole(BuildContext context, UserRole role) async {
    await saveUserRole(role);

    if (role == UserRole.responder) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => QuizPage()),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => ObserverHomePage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Welcome to Danoggin")),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              "Who are you?",
              style: TextStyle(fontSize: 22),
            ),
            SizedBox(height: 32),
            ElevatedButton.icon(
              icon: Icon(Icons.person),
              label: Text("Responder"),
              onPressed: () => selectRole(context, UserRole.responder),
            ),
            SizedBox(height: 16),
            ElevatedButton.icon(
              icon: Icon(Icons.visibility),
              label: Text("Observer"),
              onPressed: () => selectRole(context, UserRole.observer),
            ),
          ],
        ),
      ),
    );
  }
}
