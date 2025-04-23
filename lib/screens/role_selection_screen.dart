import 'package:flutter/material.dart';
import 'package:danoggin/models/user_role.dart';
import 'package:danoggin/screens/quiz_page.dart';
import 'package:danoggin/screens/observer_page.dart';
import 'package:danoggin/repositories/user_repository.dart';
import 'package:danoggin/services/auth_service.dart';
import 'dart:math';

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  UserRole? selectedRole;
  final TextEditingController nameController = TextEditingController();

  Future<void> _applyRole() async {
    final name = nameController.text.trim();
    if (selectedRole == null || name.isEmpty) return;

    final uid = AuthService.currentUserId;
    final inviteCode = selectedRole == UserRole.responder
        ? _generateInviteCode()
        : null;

    await UserRepository.createUserProfile(
      uid: uid,
      name: name,
      role: selectedRole!,
      inviteCode: inviteCode,
    );

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => selectedRole == UserRole.responder
            ? QuizPage(currentRole: selectedRole!)
            : const ObserverPage(),
      ),
    );
  }

  String _generateInviteCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rand = Random.secure();
    return List.generate(6, (index) => chars[rand.nextInt(chars.length)]).join();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Set this property to true to allow the screen to resize
      resizeToAvoidBottomInset: true,
      appBar: AppBar(title: const Text('Select Your Role')),
      // Wrap the body in a SingleChildScrollView
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              const Text('Please enter your name:', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 8),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  hintText: 'Your full name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
              const Text('Choose your role:', style: TextStyle(fontSize: 18)),
              RadioListTile<UserRole>(
                title: const Text('Responder'),
                value: UserRole.responder,
                groupValue: selectedRole,
                onChanged: (value) => setState(() => selectedRole = value),
              ),
              RadioListTile<UserRole>(
                title: const Text('Observer'),
                value: UserRole.observer,
                groupValue: selectedRole,
                onChanged: (value) => setState(() => selectedRole = value),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                icon: const Icon(Icons.check),
                label: const Text('Continue'),
                onPressed: _applyRole,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}