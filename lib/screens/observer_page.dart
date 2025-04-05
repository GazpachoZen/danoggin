// Copyright (c) 2025, Blue Vista Solutions.  All rights reserved.
//
// This source code is part of the Danoggin project and is intended for 
// internal or authorized use only. Unauthorized copying, modification, or 
// distribution of this file, via any medium, is strictly prohibited. For 
// licensing or permissions, contact: ivory@blue-vistas.com
//------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_role.dart';
import 'settings_page.dart';

class ObserverPage extends StatefulWidget {
  const ObserverPage({super.key});

  @override
  State<ObserverPage> createState() => _ObserverPageState();
}

class _ObserverPageState extends State<ObserverPage> {
  late UserRole currentRole;

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  Future<void> _loadRole() async {
    final prefs = await SharedPreferences.getInstance();
    final roleStr = prefs.getString('userRole');
    setState(() {
      currentRole = UserRoleExtension.fromString(roleStr) ?? UserRole.observer;
    });
  }

  void _openSettings() async {
    final newRole = await Navigator.push<UserRole>(
      context,
      MaterialPageRoute(
        builder: (context) => SettingsPage(currentRole: currentRole),
      ),
    );
    if (newRole != null && newRole != currentRole) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('userRole', newRole.name);
      setState(() {
        currentRole = newRole;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Danoggin (${currentRole.name[0].toUpperCase()}${currentRole.name.substring(1)})'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: const Center(
        child: Text('This is the observer view — coming soon!'),
      ),
    );
  }
}
