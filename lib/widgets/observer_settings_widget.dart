//------------------------------------------------------------------------
// Copyright (c) 2025, Blue Vista Solutions.  All rights reserved.
//
// This source code is part of the Danoggin project and is intended for
// internal or authorized use only. Unauthorized copying, modification, or
// distribution of this file, via any medium, is strictly prohibited. For
// licensing or permissions, contact: danoggin@blue-vistas.com
//------------------------------------------------------------------------
import 'package:danoggin/models/user_role.dart';
import 'package:danoggin/utils/logger.dart';
import 'package:flutter/material.dart';
import 'package:danoggin/screens/observer_manage_responders_screen.dart';
import 'package:danoggin/repositories/responder_settings_repository.dart';
import 'package:danoggin/services/auth_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';
import 'package:danoggin/services/notifications/notification_manager.dart';

// Development mode flag - set to false for production
const bool kDevModeEnabled = true;

class ObserverSettingsWidget extends StatefulWidget {
  // Add a callback for relationship changes
  final VoidCallback? onRelationshipsChanged;

  const ObserverSettingsWidget({
    super.key,
    this.onRelationshipsChanged,
  });

  @override
  State<ObserverSettingsWidget> createState() => _ObserverSettingsWidgetState();
}

class _ObserverSettingsWidgetState extends State<ObserverSettingsWidget> {
  double inactivityThresholdHours = 24; // Default: 24 hours

  // Min/max settings for inactivity threshold based on dev mode
  final double _minInactivityHours = kDevModeEnabled ? 1 : 6;
  final double _maxInactivityHours = 72;
  final int _inactivityDivisions = kDevModeEnabled ? 71 : 11;

  @override
  void initState() {
    super.initState();
    _loadInactivityThreshold();
  }

  Future<void> _loadInactivityThreshold() async {
    try {
      final uid = AuthService.currentUserId;
      final threshold =
          await ResponderSettingsRepository.getInactivityThreshold(uid);
      setState(() {
        inactivityThresholdHours = threshold.toDouble();
      });
    } catch (e) {
      Logger().e('Error loading inactivity threshold: $e');
    }
  }

  Future<void> _savePrefs() async {
    try {
      // Save inactivity threshold to Firestore
      final uid = AuthService.currentUserId;
      await ResponderSettingsRepository.saveInactivityThreshold(
        observerUid: uid,
        thresholdHours: inactivityThresholdHours.round(),
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Settings saved successfully'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      Logger().e('Error saving inactivity threshold: $e');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving settings: $e'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Inactivity threshold setting
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
                'Inactivity alert threshold: ${inactivityThresholdHours.round()} hours',
                style: TextStyle(fontSize: 16, color: Colors.deepPurple)),
            Text(
                'Range: ${_minInactivityHours.round()}-${_maxInactivityHours.round()}',
                style: TextStyle(fontSize: 14, color: Colors.grey)),
          ],
        ),
        Slider(
          value: inactivityThresholdHours,
          min: _minInactivityHours,
          max: _maxInactivityHours,
          divisions: _inactivityDivisions,
          label: '${inactivityThresholdHours.round()} hours',
          onChanged: (val) => setState(() => inactivityThresholdHours = val),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Text(
            kDevModeEnabled
                ? 'DEV MODE: Using 1-hour minimum for testing (set kDevModeEnabled = false for production)'
                : 'Get alerted if a responder has no activity for longer than this threshold during their active hours.',
            style: TextStyle(
              fontSize: 12,
              color: kDevModeEnabled ? Colors.red[600] : Colors.grey[600],
              fontStyle: FontStyle.italic,
              fontWeight: kDevModeEnabled ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Save button
        Center(
          child: ElevatedButton(
            onPressed: _savePrefs,
            child: const Text('Save Settings'),
          ),
        ),

        // Manage responders section
        ListTile(
          leading: const Icon(Icons.people),
          title: Text('Manage ${UserRole.responder.displayLabelPlural}'),
          subtitle: const Text('Add or remove people you monitor'),
          trailing: const Icon(Icons.arrow_forward_ios, size: 16),
          onTap: () async {
            // Wait for result from manage responders screen
            final relationshipsChanged = await Navigator.of(context).push<bool>(
              MaterialPageRoute(
                builder: (_) => const ObserverManageRespondersScreen(),
              ),
            );

            // If relationships changed, notify our parent
            if (relationshipsChanged == true &&
                widget.onRelationshipsChanged != null) {
              widget.onRelationshipsChanged!();
            }
          },
        ),

        // Enhanced FCM test section
        ListTile(
          leading: const Icon(Icons.message),
          title: const Text('Test FCM Setup'),
          subtitle: const Text('Verify FCM token generation and storage'),
          onTap: () async {
            try {
              // Check if Firebase Messaging is available
              NotificationManager().log('=== FCM TEST BUTTON PRESSED (Observer) ===');
              NotificationManager().log('Checking FCM setup...');
              
              final messaging = FirebaseMessaging.instance;
              
              // Request permission explicitly
              NotificationSettings settings = await messaging.requestPermission(
                alert: true,
                announcement: false,
                badge: true,
                carPlay: false,
                criticalAlert: false,
                provisional: false,
                sound: true,
              );
              
              NotificationManager().log('Permission granted: ${settings.authorizationStatus}');
              
              final token = await messaging.getToken();
              if (token != null) {
                NotificationManager().log('FCM Token retrieved successfully');
                NotificationManager().log('Token length: ${token.length}');
                
                // Trigger FCM initialization which should save the token to Firestore
                await NotificationManager().initializeFCM();
                
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text('FCM Debug Info'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Permission: ${settings.authorizationStatus}'),
                        SizedBox(height: 8),
                        Text('Token generated: ${token.isNotEmpty ? "Yes" : "No"}'),
                        SizedBox(height: 8),
                        Text('Token length: ${token.length}'),
                        SizedBox(height: 16),
                        Text('Full token:'),
                        Container(
                          height: 100,
                          child: SingleChildScrollView(
                            child: SelectableText(
                              token,
                              style: TextStyle(fontSize: 10, fontFamily: 'monospace'),
                            ),
                          ),
                        ),
                        SizedBox(height: 16),
                        Text('Check logs for Firestore save operation details.',
                             style: TextStyle(fontStyle: FontStyle.italic, color: Colors.blue[700])),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: token));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Token copied to clipboard'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                        child: Text('Copy Token'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text('Close'),
                      ),
                    ],
                  ),
                );
              } else {
                NotificationManager().log('FCM token is null - indicates a problem');
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('FCM token generation failed'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            } catch (e) {
              NotificationManager().log('FCM test error: $e');
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('FCM error: $e'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          },
        ),
      ],
    );
  }
}