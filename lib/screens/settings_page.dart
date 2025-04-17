import 'package:danoggin/widgets/observer_settings_widget.dart';
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
  // Add a flag to track if relationships have changed
  bool _relationshipsChanged = false;

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
  void dispose() {
    // If we're popping back to the observer page and relationships changed
    if (_relationshipsChanged) {
      Navigator.of(context).pop(true);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDirty = selectedRole != widget.currentRole;

    return WillPopScope(
      onWillPop: () async {
        // Signal back to parent page if relationships have changed
        if (_relationshipsChanged) {
          Navigator.of(context).pop(true);
          return false; // We handled the navigation
        }
        return true; // Allow normal back behavior
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Settings'),
          // Add a custom back button that returns our result
          leading: IconButton(
            icon: Icon(Icons.arrow_back),
            onPressed: () {
              if (_relationshipsChanged) {
                Navigator.of(context).pop(true);
              } else {
                Navigator.of(context).pop();
              }
            },
          ),
        ),
        // Use a SingleChildScrollView to wrap the entire content
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              children: [
                // Role-specific settings
                widget.currentRole == UserRole.responder
                    ? ResponderSettingsWidget(
                        // Add a callback to receive relationship changes
                        onRelationshipsChanged: () {
                          setState(() {
                            _relationshipsChanged = true;
                          });
                        },
                      )
                    : ObserverSettingsWidget(
                        // Add a callback to receive relationship changes
                        onRelationshipsChanged: () {
                          setState(() {
                            _relationshipsChanged = true;
                          });
                        },
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
                // Add padding at the bottom for better scrolling experience
                SizedBox(height: 20),
              ],
            ),
          ),
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