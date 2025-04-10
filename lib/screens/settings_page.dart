import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:danoggin/models/user_role.dart';
import 'package:danoggin/widgets/responder_settings_widget.dart';

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
    Navigator.pop(context, selectedRole);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Expanded(
              child: widget.currentRole == UserRole.responder
                  ? const ResponderSettingsWidget()
                  : const Center(
                      child: Text('Observer settings coming soon...')),
            ),
            const SizedBox(height: 24),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Your Current Role',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    RadioListTile<UserRole>(
                      title: const Text('Responder'),
                      value: UserRole.responder,
                      groupValue: selectedRole,
                      onChanged: (value) =>
                          setState(() => selectedRole = value!),
                    ),
                    RadioListTile<UserRole>(
                      title: const Text('Observer'),
                      value: UserRole.observer,
                      groupValue: selectedRole,
                      onChanged: (value) =>
                          setState(() => selectedRole = value!),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.check),
                        label: const Text('Apply'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurple,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                        ),
                        onPressed: selectedRole == widget.currentRole
                            ? null
                            : _applyRoleChange,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
