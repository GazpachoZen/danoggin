
import 'package:flutter/material.dart';
import 'package:danoggin/models/user_role.dart';
import 'package:danoggin/screens/quiz_page.dart';
import 'package:danoggin/screens/observer_page.dart';
import 'package:danoggin/repositories/user_repository.dart';
import 'package:danoggin/services/auth_service.dart';

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  UserRole? selectedRole;

  Future<void> _applyRole() async {
    if (selectedRole == null) return;

    final uid = AuthService.currentUserId;
    await UserRepository.createUserIfNotExists(uid, selectedRole!);
    print('Role ${selectedRole!.name} stored for user $uid');

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => selectedRole == UserRole.responder
            ? QuizPage()
            : ObserverPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Select Your Role')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const Text('Please choose your role:', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 24),
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
    );
  }
}
