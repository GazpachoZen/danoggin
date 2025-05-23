// Copyright (c) 2025, Blue Vista Solutions.  All rights reserved.
//
// This source code is part of the Danoggin project and is intended for 
// internal or authorized use only. Unauthorized copying, modification, or 
// distribution of this file, via any medium, is strictly prohibited. For 
// licensing or permissions, contact: ivory@blue-vistas.com
//------------------------------------------------------------------------

import 'package:shared_preferences/shared_preferences.dart';

enum UserRole {
  responder,
  observer,
}

Future<void> saveUserRole(UserRole role) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('userRole', role.name);
}

Future<UserRole?> loadUserRole() async {
  final prefs = await SharedPreferences.getInstance();
  final roleStr = prefs.getString('userRole');
  if (roleStr == null) return null;

  for (final role in UserRole.values) {
    if (role.name == roleStr) return role;
  }

  return null; // not found
}

extension UserRoleExtension on UserRole {
  static UserRole? fromString(String? roleStr) {
    if (roleStr == null) return null;
    return UserRole.values.firstWhere(
      (e) => e.name == roleStr,
      orElse: () => UserRole.responder, // or null, if you'd rather crash safely
    );
  }

  /// Get the user-facing display label for this role
  String get displayLabel {
    switch (this) {
      case UserRole.responder:
        return 'Main user';
      case UserRole.observer:
        return 'Support partner';
    }
  }

  /// Get the plural form of the user-facing display label
  String get displayLabelPlural {
    switch (this) {
      case UserRole.responder:
        return 'Main users';
      case UserRole.observer:
        return 'Support partners';
    }
  }

  /// Get a brief description of what this role does
  String get description {
    switch (this) {
      case UserRole.responder:
        return 'Receives check-in reminders and answers questions';
      case UserRole.observer:
        return 'Monitors main user activity and receives alerts';
    }
  }
}