// Copyright (c) 2025, Blue Vista Solutions.  All rights reserved.
//
// This source code is part of the Danoggin project and is intended for
// internal or authorized use only. Unauthorized copying, modification, or
// distribution of this file, via any medium, is strictly prohibited. For
// licensing or permissions, contact: ivory@blue-vistas.com
//------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:danoggin/models/user_role.dart';
import 'quiz_page.dart';
import 'observer_page.dart';
import 'package:danoggin/services/notification_service.dart';
import 'package:danoggin/widgets/responder_settings_widget.dart';

class SettingsPage extends StatefulWidget {
  final UserRole currentRole;

  const SettingsPage({super.key, required this.currentRole});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late UserRole _selectedRole;

  @override
  void initState() {
    super.initState();
    _selectedRole = widget.currentRole;
  }

  Future<void> _saveAndNavigate(UserRole role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('userRole', role.name);

    // Decide the destination based on role
    Widget destination;
    if (role == UserRole.responder) {
      destination = QuizPage();
    } else {
      destination = ObserverPage();
    }

    if (!mounted) return;

    // Replace the entire route stack
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => destination),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Settings")),
      body: Column(
        children: [
          const SizedBox(height: 10),
          _selectedRole == UserRole.responder
              ? const ResponderSettingsWidget()
              : const Text('Observer settings coming soon...'),
          const SizedBox(height: 20),
          const Text("Select Your Role", style: TextStyle(fontSize: 20)),
          RadioListTile<UserRole>(
            title: const Text('Responder'),
            value: UserRole.responder,
            groupValue: _selectedRole,
            onChanged: (value) => setState(() => _selectedRole = value!),
          ),
          RadioListTile<UserRole>(
            title: const Text('Observer'),
            value: UserRole.observer,
            groupValue: _selectedRole,
            onChanged: (value) => setState(() => _selectedRole = value!),
          ),
          ElevatedButton.icon(
            onPressed: () => _saveAndNavigate(_selectedRole),
            icon: const Icon(Icons.check),
            label: const Text("Apply"),
          ),
          if (_selectedRole == UserRole.responder) ...[
            const Text("Responder settings would go here"),
          ] else if (_selectedRole == UserRole.observer) ...[
            const Text("Observer settings would go here"),
          ]
        ],
      ),
    );
  }
}
