// Copyright (c) 2025, Blue Vista Solutions.  All rights reserved.
//
// This source code is part of the Danoggin project and is intended for
// internal or authorized use only. Unauthorized copying, modification, or
// distribution of this file, via any medium, is strictly prohibited. For
// licensing or permissions, contact: danoggin@blue-vistas.com
//------------------------------------------------------------------------

import 'package:danoggin/utils/logger.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:danoggin/screens/responder_invite_code_screen.dart';
import 'package:danoggin/screens/responder_manage_observers_screen.dart';
import 'package:danoggin/widgets/question_pack_selector_widget.dart';
import 'package:danoggin/repositories/responder_settings_repository.dart';
import 'package:danoggin/services/auth_service.dart';
import 'package:danoggin/services/notifications/notification_manager.dart';
import 'package:danoggin/services/check_in_scheduler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ResponderSettingsWidget extends StatefulWidget {
  // Add callback for relationship changes
  final VoidCallback? onRelationshipsChanged;

  const ResponderSettingsWidget({
    super.key,
    this.onRelationshipsChanged,
  });

  @override
  State<ResponderSettingsWidget> createState() =>
      _ResponderSettingsWidgetState();
}

class _ResponderSettingsWidgetState extends State<ResponderSettingsWidget> {
  TimeOfDay startHour = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay endHour = const TimeOfDay(hour: 20, minute: 0);
  double alertFrequencyMinutes = 5;
  double timeoutMinutes = 1;

  // Constants for constraints
  final double maxTimeoutMinutes = 15.0;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();

    // Load settings from preferences
    final savedStartHour = _getTimeOfDay(prefs.getString('startHour'));
    final savedEndHour = _getTimeOfDay(prefs.getString('endHour'));
    final savedAlertFrequency = prefs.getDouble('alertFrequency');
    final savedTimeout = prefs.getDouble('timeoutDuration');

    setState(() {
      startHour = savedStartHour ?? startHour;
      endHour = savedEndHour ?? endHour;

      // Load alert frequency first
      if (savedAlertFrequency != null) {
        alertFrequencyMinutes = savedAlertFrequency;
      }

      // Then load timeout ensuring it respects the constraints
      if (savedTimeout != null) {
        timeoutMinutes = _constrainTimeout(savedTimeout);
      }
    });
  }

  // Helper method to constrain timeout value based on alert frequency
  double _constrainTimeout(double timeout) {
    // Never more than maxTimeoutMinutes
    double constrainedTimeout =
        timeout > maxTimeoutMinutes ? maxTimeoutMinutes : timeout;
    // Never more than half of alert frequency
    constrainedTimeout = constrainedTimeout > alertFrequencyMinutes / 2
        ? alertFrequencyMinutes / 2
        : constrainedTimeout;
    return constrainedTimeout;
  }

  // Get maximum timeout value based on current alert frequency
  double get _maxTimeout {
    return (alertFrequencyMinutes / 2) < maxTimeoutMinutes
        ? (alertFrequencyMinutes / 2)
        : maxTimeoutMinutes;
  }

  TimeOfDay? _getTimeOfDay(String? value) {
    if (value == null) return null;
    final parts = value.split(':');
    if (parts.length != 2) return null;
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  String _formatTimeOfDay(TimeOfDay tod) =>
      '${tod.hour.toString().padLeft(2, '0')}:${tod.minute.toString().padLeft(2, '0')}';

  String _formatTimeOfDayAMPM(TimeOfDay tod) {
    final now = DateTime.now();
    final dt = DateTime(now.year, now.month, now.day, tod.hour, tod.minute);
    final local = TimeOfDay.fromDateTime(dt);
    return local.format(context); // Uses device locale and AM/PM
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();

    // Ensure timeout conforms to constraints before saving
    timeoutMinutes = _constrainTimeout(timeoutMinutes);

    // Format the hours for storage
    final startHourStr = _formatTimeOfDay(startHour);
    final endHourStr = _formatTimeOfDay(endHour);

    // Save locally to SharedPreferences
    await prefs.setString('startHour', startHourStr);
    await prefs.setString('endHour', endHourStr);
    await prefs.setDouble('alertFrequency', alertFrequencyMinutes);
    await prefs.setDouble('timeoutDuration', timeoutMinutes);

    // Sync to Firestore for observer visibility
    try {
      final uid = AuthService.currentUserId;
      await ResponderSettingsRepository.saveActiveHours(
        uid: uid,
        startHour: startHourStr,
        endHour: endHourStr,
      );

      // Update the check-in schedule based on new settings
      await _updateCheckInSchedule();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Settings saved successfully'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      Logger().e('Error syncing settings to Firestore: $e');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving cloud settings: $e'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  /// Update the check-in schedule after user changes settings
  Future<void> _updateCheckInSchedule() async {
    try {
      // Get current timezone from Firestore
      final uid = AuthService.currentUserId;
      final userDoc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();

      String timeZone = 'UTC'; // Default fallback
      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;
        final activeHours = userData['activeHours'] as Map<String, dynamic>?;
        timeZone = activeHours?['timeZone'] as String? ?? 'UTC';
      }

      // Call the scheduler with new settings
      await CheckInScheduler.updateAfterSettingsChange(
        intervalMinutes: alertFrequencyMinutes.round(),
        activeStartHour: startHour,
        activeEndHour: endHour,
        timeZone: timeZone,
      );

      Logger().i(
          'ResponderSettings: Check-in schedule updated after settings change');
    } catch (e) {
      Logger().i('ResponderSettings: Error updating check-in schedule: $e');
      // Don't re-throw since settings were saved successfully
      // Just log the error for debugging
    }
  }

  Future<void> _pickTime(BuildContext context, bool isStart) async {
    final initialTime = isStart ? startHour : endHour;
    final picked =
        await showTimePicker(context: context, initialTime: initialTime);
    if (picked != null) {
      setState(() {
        if (isStart) {
          startHour = picked;
        } else {
          endHour = picked;
        }
      });
    }
  }

  // Handler for pack selection changes
  void _handlePackSelectionChanged() {
    // Just trigger the callback to parent if needed
    if (widget.onRelationshipsChanged != null) {
      widget.onRelationshipsChanged!();
    }
  }

  // Handle alert frequency changes
  void _handleAlertFrequencyChanged(double newValue) {
    setState(() {
      alertFrequencyMinutes = newValue;

      // Auto-constrain timeout if needed
      if (timeoutMinutes > _maxTimeout) {
        timeoutMinutes = _maxTimeout;
      }
    });
  }

  // Handle timeout changes
  void _handleTimeoutChanged(double newValue) {
    setState(() {
      // First, apply the new timeout value
      timeoutMinutes = newValue;

      // If the new timeout is greater than half the alert frequency,
      // increase the alert frequency to maintain the 2:1 ratio
      if (timeoutMinutes > alertFrequencyMinutes / 2) {
        alertFrequencyMinutes = timeoutMinutes * 2;

        // Round up to the nearest minute for cleaner UI
        alertFrequencyMinutes = (alertFrequencyMinutes.ceil()).toDouble();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Calculate the current max timeout based on our constraints
    final currentMaxTimeout = _maxTimeout;

    // Determine the number of divisions for the timeout slider based on max value
    final timeoutDivisions =
        (currentMaxTimeout * 2).round(); // 0.5 minute increments

    return Padding(
      padding: const EdgeInsets.only(bottom: 32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 16.0),
            child: Text('Hours of Operation',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          Row(
            children: [
              TextButton(
                onPressed: () => _pickTime(context, true),
                child: Text('Start: ${_formatTimeOfDayAMPM(startHour)}'),
              ),
              TextButton(
                onPressed: () => _pickTime(context, false),
                child: Text('End: ${_formatTimeOfDayAMPM(endHour)}'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('Alert Frequency: ${alertFrequencyMinutes.round()} min',
              style: TextStyle(fontWeight: FontWeight.bold)),
          Slider(
            value: alertFrequencyMinutes,
            min: timeoutMinutes * 2, // Minimum is twice the current timeout
            max: 360,
            divisions: 71,
            label: '${alertFrequencyMinutes.round()} min',
            onChanged: _handleAlertFrequencyChanged,
          ),
          const SizedBox(height: 8),
          Text('Response Timeout: ${timeoutMinutes.toStringAsFixed(1)} min',
              style: TextStyle(fontWeight: FontWeight.bold)),
          Slider(
            value: timeoutMinutes,
            min: 0.5,
            max: currentMaxTimeout, // Dynamically calculated max
            divisions: timeoutDivisions,
            label: '${timeoutMinutes.toStringAsFixed(1)} min',
            onChanged: _handleTimeoutChanged,
          ),
          // Add a helper text to explain constraints
          Padding(
            padding: const EdgeInsets.only(top: 4.0, bottom: 8.0),
            child: Text(
              'Note: Response timeout cannot exceed half of alert frequency or 15 minutes.',
              style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: ElevatedButton(
              onPressed: _savePrefs,
              child: const Text('Save Settings'),
            ),
          ),
          const Divider(height: 32),

          // Add the question pack selector with better spacing
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: QuestionPackSelectorWidget(
              onPacksChanged: _handlePackSelectionChanged,
            ),
          ),

          // Enhanced FCM test section
          ListTile(
            leading: const Icon(Icons.message),
            title: const Text('Test FCM Notifications'),
            subtitle: const Text('Test complete notification pipeline'),
            onTap: () async {
              try {
                // Show loading state
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Testing FCM notification delivery...'),
                    duration: Duration(seconds: 2),
                  ),
                );

                NotificationManager()
                    .log('=== FCM PIPELINE TEST (Responder Settings) ===');

                final messaging = FirebaseMessaging.instance;

                // Ensure we have permission
                NotificationSettings settings =
                    await messaging.requestPermission(
                  alert: true,
                  badge: true,
                  sound: true,
                );

                if (settings.authorizationStatus !=
                    AuthorizationStatus.authorized) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Notification permission not granted'),
                      backgroundColor: Colors.orange,
                      duration: Duration(seconds: 3),
                    ),
                  );
                  return;
                }

                // Get token and test the full pipeline
                final token = await messaging.getToken();
                if (token == null) {
                  NotificationManager().log('FCM token is null - test failed');
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to get FCM token'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                // Ensure token is saved to Firestore
                await NotificationManager().initializeFCM();

                // Test the complete pipeline via Cloud Function
                final response = await http.post(
                  Uri.parse(
                      'https://us-central1-danoggin-d0478.cloudfunctions.net/testFCM'),
                  headers: {'Content-Type': 'application/json'},
                  body: json.encode({
                    'token': token,
                    'message':
                        'Test from responder settings - pipeline working!',
                  }),
                );

                if (response.statusCode == 200) {
                  NotificationManager().log('FCM pipeline test successful');
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          'FCM test successful! Check your notification tray.'),
                      backgroundColor: Colors.green,
                      duration: Duration(seconds: 4),
                    ),
                  );
                } else {
                  NotificationManager()
                      .log('FCM pipeline test failed: ${response.statusCode}');
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('FCM test failed: ${response.body}'),
                      backgroundColor: Colors.red,
                      duration: Duration(seconds: 3),
                    ),
                  );
                }
              } catch (e) {
                NotificationManager().log('FCM pipeline test error: $e');
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('FCM test error: $e'),
                    backgroundColor: Colors.red,
                    duration: Duration(seconds: 3),
                  ),
                );
              }
            },
          ),
          const Divider(height: 32),
          ListTile(
            leading: const Icon(Icons.key),
            title: const Text('Show my invite code'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ResponderInviteCodeScreen(),
                ),
              );
            },
          ),
          // Add new option for managing observers
          ListTile(
            leading: const Icon(Icons.people),
            title: const Text('Who is observing me'),
            subtitle: const Text('See and manage observers'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () async {
              // Navigate to manage observers screen and await result
              final relationshipsChanged =
                  await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => const ResponderManageObserversScreen(),
                ),
              );

              // If relationships changed and we have a callback, notify parent
              if (relationshipsChanged == true &&
                  widget.onRelationshipsChanged != null) {
                widget.onRelationshipsChanged!();
              }
            },
          ),
          // Add extra padding at the bottom
          SizedBox(height: 32),
        ],
      ),
    );
  }
}
