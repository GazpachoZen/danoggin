import 'package:danoggin/utils/logger.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:danoggin/models/user_role.dart';

class UserRepository {
  static final _usersRef = FirebaseFirestore.instance.collection('users');

  static Future<void> createUserProfile({
    required String uid,
    required String name,
    required UserRole role,
    String? inviteCode,
  }) async {
    final doc = _usersRef.doc(uid);
    final snapshot = await doc.get();

    // Prepare base user data
    final userData = {
      'name': name,
      'role': role.name,
      'createdAt': FieldValue.serverTimestamp(),
      if (inviteCode != null) 'inviteCode': inviteCode,
    };

    // Add role-specific data
    if (role == UserRole.responder) {
      // Set up initial active hours (default 8 AM to 8 PM)
      userData['activeHours'] = {
        'startHour': '08:00',
        'endHour': '20:00',
        'timeZone': 'UTC', // Will be updated when user saves settings
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // Set up initial check-in schedule
      final now = DateTime.now();
      
      // Calculate initial next check-in time (5 minutes from now by default)
      final initialNextCheckIn = _calculateInitialCheckInTime(now);
      
      userData['checkInSettings'] = {
        'intervalMinutes': 5,        // Default 5-minute intervals
        'timeoutMinutes': 1,         // Default 1-minute timeout
        'enabled': true,             // Enabled by default
        'nextCheckInTime': Timestamp.fromDate(initialNextCheckIn),
        'lastCheckInTime': null,     // No previous check-ins yet
        'lastUpdated': FieldValue.serverTimestamp(),
      };
      
      Logger().i('UserRepository: Created responder with initial check-in scheduled for ${initialNextCheckIn.toIso8601String()}');
    }

    // Create or update the user document
    if (!snapshot.exists) {
      await doc.set(userData);
      Logger().i('UserRepository: Created new user profile for $uid');
    } else {
      await doc.update(userData);
      Logger().i('UserRepository: Updated existing user profile for $uid');
    }
  }

  /// Calculate the initial check-in time for a new responder
  /// This ensures they get their first check-in prompt within 5 minutes of signup
  static DateTime _calculateInitialCheckInTime(DateTime baseTime) {
    // For new users, schedule first check-in in 5 minutes
    // This gives them time to complete onboarding and see the app in action
    return baseTime.add(Duration(minutes: 5));
  }

  static Future<UserRole?> getUserRole(String uid) async {
    final snapshot = await _usersRef.doc(uid).get();
    if (!snapshot.exists) return null;

    final data = snapshot.data();
    final roleStr = data?['role'] as String?;
    return UserRoleExtension.fromString(roleStr);
  }

  static Future<void> updateUserRole(String uid, UserRole role) async {
    await _usersRef.doc(uid).update({'role': role.name});
  }
}