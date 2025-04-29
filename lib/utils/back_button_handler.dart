import 'dart:async';
import 'package:flutter/material.dart';
import 'package:danoggin/models/user_role.dart';

class BackButtonHandler {
  // Singleton instance
  static final BackButtonHandler _instance = BackButtonHandler._internal();
  factory BackButtonHandler() => _instance;
  BackButtonHandler._internal();

  // Track the last back press time
  DateTime? _lastBackPressTime;
  // Configurable timeout duration
  final Duration _exitTimeoutDuration = const Duration(milliseconds: 2000);

  /// Handles back button press with double-press pattern and confirmation dialog
  /// Returns true if app should be exited, false otherwise
  Future<bool> handleBackPress(BuildContext context, UserRole role) async {
    final now = DateTime.now();
    
    // If this is the first press or the timeout has elapsed
    if (_lastBackPressTime == null || 
        now.difference(_lastBackPressTime!) > _exitTimeoutDuration) {
      
      // Update the last press time
      _lastBackPressTime = now;
      
      // Show a message to the user
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Press back again to exit'),
          duration: Duration(milliseconds: 1500),
        ),
      );
      
      // Don't exit the app yet
      return false;
    }
    
    // This is the second press within the timeout period
    // Reset the last press time
    _lastBackPressTime = null;
    
    // Show confirmation dialog based on user role
    return await _showExitConfirmationDialog(context, role);
  }
  
  Future<bool> _showExitConfirmationDialog(BuildContext context, UserRole role) async {
    String title = 'Exit Danoggin?';
    String message;
    
    // Customize message based on user role
    if (role == UserRole.responder) {
      message = 'Are you sure you want to exit Danoggin? You may miss important check-in notifications.';
    } else { // Observer role
      message = 'Are you sure you want to exit Danoggin? You will not receive alerts about responder check-ins while the app is closed.';
    }
    
    // Show the dialog and wait for result
    final shouldExit = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // User must respond
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false), // Don't exit
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true), // Confirm exit
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[400], // Warning color
            ),
            child: const Text('Exit'),
          ),
        ],
      ),
    );
    
    // If dialog was dismissed without a selection or "Cancel" was pressed
    return shouldExit ?? false;
  }
}