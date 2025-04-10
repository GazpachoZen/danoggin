
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:danoggin/models/user_role.dart';
import 'package:danoggin/widgets/responder_settings_widget.dart';
import 'package:danoggin/screens/quiz_page.dart';
import 'package:danoggin/screens/observer_page.dart';

class SettingsPage extends StatefulWidget {
  final UserRole currentRole;
  const SettingsPage({super.key, required this.currentRole});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late UserRole selectedRole;

  @override
  void initState() {
    super.initState();
    selectedRole = widget.currentRole;
  }

  Future<void> _applyRoleChange() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('userRole', selectedRole.name);
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => selectedRole == UserRole.responder
            ? QuizPage()
            : ObserverPage(),
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDirty = selectedRole != widget.currentRole;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            // Role-specific settings
            Expanded(
              child: widget.currentRole == UserRole.responder
                  ? const ResponderSettingsWidget()
                  : const Center(child: Text('Observer settings coming soon...')),
            ),

            // Role selection section (always shown last)
            const Divider(thickness: 1.2, height: 32),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Switch Role (rarely needed)',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  _buildRoleSelector(),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.check),
                      label: const Text('Apply'),
                      onPressed: isDirty ? _applyRoleChange : null,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                        backgroundColor: isDirty ? Colors.deepPurple : Colors.grey,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleSelector() {
    return Column(
      children: UserRole.values.map((role) {
        return RadioListTile<UserRole>(
          dense: true,
          contentPadding: EdgeInsets.zero,
          visualDensity: const VisualDensity(vertical: -4),
          title: Text(role.name[0].toUpperCase() + role.name.substring(1)),
          value: role,
          groupValue: selectedRole,
          onChanged: (value) => setState(() => selectedRole = value!),
        );
      }).toList(),
    );
  }
}
