import 'package:danoggin/screens/about_screen.dart';
import 'package:danoggin/screens/web_view_screen.dart';
import 'package:flutter/material.dart';
import 'package:danoggin/screens/logs_viewer_screen.dart';
import 'package:danoggin/widgets/observer_settings_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:danoggin/models/user_role.dart';
import 'package:danoggin/widgets/responder_settings_widget.dart';
import 'package:danoggin/screens/quiz_page.dart';
import 'package:danoggin/screens/observer_page.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:danoggin/services/notifications/notification_manager.dart';
import 'package:danoggin/controllers/observer_controller.dart';

const bool kDevModeEnabled = true; // Set to false for production

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
            ? QuizPage(
                currentRole: selectedRole) // Pass the currentRole parameter
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
              Navigator.of(context).pop(_relationshipsChanged);
            },
          ),
        ),
        // Use a SingleChildScrollView to wrap the entire content
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
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

                // Add a divider before the legal section
                const Divider(thickness: 1.2, height: 32),

                // Add new legal and information section
                _buildLegalSection(),

                // Developer tools (existing code)
                _buildDeveloperTools(context, isDirty),

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
          title: Text(role.displayLabel),
          value: role,
          groupValue: selectedRole,
          onChanged: (value) => setState(() => selectedRole = value!),
        );
      }).toList(),
    );
  }

  Widget _buildDeveloperTools(BuildContext context, bool isDirty) {
    // Only show in dev mode
    if (!kDevModeEnabled) {
      return const SizedBox.shrink(); // Hidden in production
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(thickness: 1.2, height: 32),

        // Add a more prominent header for the debug section
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            border: Border.all(color: Colors.red.shade200),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              Icon(Icons.developer_mode, color: Colors.red.shade700),
              const SizedBox(width: 8),
              Text(
                'DEVELOPER MODE',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.red.shade700,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Move role selector here - inside the debug container
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
                'Switch Role',
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 10),
                    backgroundColor: isDirty ? Colors.deepPurple : Colors.grey,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Log viewer option (existing code)
        ListTile(
          leading: const Icon(Icons.list),
          title: const Text('View Notification Logs'),
          subtitle: const Text('Debug message history'),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => LogsViewerScreen(),
              ),
            );
          },
        ),

        // Notification test option (existing code)
        ListTile(
          leading: const Icon(Icons.notifications),
          title: const Text('Test Notification System'),
          subtitle: Text(widget.currentRole == UserRole.responder
              ? 'Test FCM pipeline (Responder)'
              : 'Test notification delivery (Observer)'),
          onTap: () async {
            if (widget.currentRole == UserRole.responder) {
              // Call the responder-specific test method (imported from quiz_page.dart)
              await _testResponderNotifications(context);
            } else {
              // Call the observer-specific test method (using controller)
              await _testObserverNotifications(context);
            }
          },
        ),

        // Add a note indicating this is development mode
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Text(
            'Development mode is enabled. These tools will not appear in production.',
            style: TextStyle(
                color: Colors.deepOrange,
                fontSize: 12,
                fontStyle: FontStyle.italic),
          ),
        ),
      ],
    );
  }

  Future<void> _testResponderNotifications(BuildContext context) async {
    try {
      // Set the current context for notifications
      NotificationManager().setCurrentContext(context);

      // Show loading indicator
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Testing FCM notification pipeline...'),
          duration: Duration(seconds: 3),
        ),
      );

      // First ensure we have a valid FCM token
      final token = await FirebaseMessaging.instance.getToken();

      if (token == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to get FCM token'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Test the full FCM pipeline by calling our Cloud Function
      final response = await http.post(
        Uri.parse(
            'https://us-central1-danoggin-d0478.cloudfunctions.net/testFCM'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'token': token,
          'message':
              'Test notification from responder app - FCM pipeline working!',
        }),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'FCM test notification sent successfully!\nCheck your notification tray.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 4),
          ),
        );

        // Log success for debugging
        NotificationManager()
            .log('FCM test notification sent via Cloud Function');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send test notification: ${response.body}'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ),
        );

        // Log failure for debugging
        NotificationManager()
            .log('FCM test failed: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error testing FCM: $e'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 4),
        ),
      );

      // Log error for debugging
      NotificationManager().log('FCM test error: $e');
    }
  }

  Future<void> _testObserverNotifications(BuildContext context) async {
    try {
      // Create a temporary controller just for testing
      final controller = ObserverController(onStateChanged: () {});

      // Use the controller's test method
      await controller.testNotifications(context);

      // Clean up the controller
      controller.dispose();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error testing observer notifications: $e'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

Widget _buildLegalSection() {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // More compact header with less padding
      Padding(
        padding: const EdgeInsets.only(left: 12.0, bottom: 4.0),
        child: Text(
          'Legal & Information',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: Colors.grey[700],
          ),
        ),
      ),
      
      // Make the list tiles more compact
      ListView(
        shrinkWrap: true,
        physics: NeverScrollableScrollPhysics(),
        children: [
          // About option - now navigates to local About screen
          ListTile(
            dense: true,
            visualDensity: VisualDensity(horizontal: 0, vertical: -2),
            leading: const Icon(Icons.info_outline, size: 20),
            title: const Text('About Danoggin', style: TextStyle(fontSize: 14)),
            trailing: const Icon(Icons.arrow_forward_ios, size: 14),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => AboutScreen(),
                ),
              );
            },
          ),
          
          // EULA option
          ListTile(
            dense: true,
            visualDensity: VisualDensity(horizontal: 0, vertical: -2),
            leading: const Icon(Icons.description_outlined, size: 20),
            title: const Text('Terms of Use (EULA)', style: TextStyle(fontSize: 14)),
            trailing: const Icon(Icons.arrow_forward_ios, size: 14),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => WebViewScreen(
                    url: 'https://blue-vistas.com/danoggin_eula.html',
                    title: 'Terms of Use',
                  ),
                ),
              );
            },
          ),
          
          // Privacy Policy option
          ListTile(
            dense: true,
            visualDensity: VisualDensity(horizontal: 0, vertical: -2),
            leading: const Icon(Icons.privacy_tip_outlined, size: 20),
            title: const Text('Privacy Policy', style: TextStyle(fontSize: 14)),
            trailing: const Icon(Icons.arrow_forward_ios, size: 14),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => WebViewScreen(
                    url: 'https://blue-vistas.com/danoggin_privacy.html',
                    title: 'Privacy Policy',
                  ),
                ),
              );
            },
          ),
          
          // Acknowledgments option
          ListTile(
            dense: true,
            visualDensity: VisualDensity(horizontal: 0, vertical: -2),
            leading: const Icon(Icons.attribution_outlined, size: 20),
            title: const Text('Acknowledgments', style: TextStyle(fontSize: 14)),
            trailing: const Icon(Icons.arrow_forward_ios, size: 14),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => WebViewScreen(
                    url: 'https://blue-vistas.com/danoggin_acknowledgements.html',
                    title: 'Acknowledgments',
                  ),
                ),
              );
            },
          ),
        ],
      ),
    ],
  );
}


}
