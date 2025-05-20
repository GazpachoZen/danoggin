import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:danoggin/utils/timezone_helper.dart';

class ResponderSettingsRepository {
  static final _usersRef = FirebaseFirestore.instance.collection('users');

  // Save responder active hours to Firestore with time zone info
  static Future<void> saveActiveHours({
    required String uid,
    required String startHour,
    required String endHour,
  }) async {
    try {
      // Get the current time zone
      final timeZone = TimezoneHelper.getCurrentTimeZone();

      await _usersRef.doc(uid).set({
        'activeHours': {
          'startHour': startHour,
          'endHour': endHour,
          'timeZone': timeZone,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        'checkInSettings': {
          'intervalMinutes': 5, // Will come from user settings
          'timeoutMinutes': 1, // Will come from user settings
          'enabled': true,
          'lastUpdated': FieldValue.serverTimestamp(),
        }
      }, SetOptions(merge: true));

      print(
          'Active hours saved to Firestore for user $uid in time zone $timeZone');
    } catch (e) {
      print('❌ Error saving active hours to Firestore: $e');
      rethrow;
    }
  }

  // Get responder active hours from Firestore
  static Future<Map<String, dynamic>?> getActiveHours(String uid) async {
    try {
      final doc = await _usersRef.doc(uid).get();
      final data = doc.data();

      if (data != null && data.containsKey('activeHours')) {
        return data['activeHours'] as Map<String, dynamic>;
      }

      return null;
    } catch (e) {
      print('❌ Error getting active hours from Firestore: $e');
      return null;
    }
  }

  // Save inactivity threshold for an observer
  static Future<void> saveInactivityThreshold({
    required String observerUid,
    required int thresholdHours,
  }) async {
    try {
      // Get the current time zone
      final timeZone = TimezoneHelper.getCurrentTimeZone();

      await _usersRef.doc(observerUid).set({
        'inactivitySettings': {
          'thresholdHours': thresholdHours,
          'timeZone': timeZone,
          'updatedAt': FieldValue.serverTimestamp(),
        }
      }, SetOptions(merge: true));

      print(
          'Inactivity threshold saved to Firestore for observer $observerUid');
    } catch (e) {
      print('❌ Error saving inactivity threshold to Firestore: $e');
      rethrow;
    }
  }

  // Get inactivity threshold for an observer
  static Future<int> getInactivityThreshold(String observerUid) async {
    try {
      final doc = await _usersRef.doc(observerUid).get();
      final data = doc.data();

      if (data != null &&
          data.containsKey('inactivitySettings') &&
          data['inactivitySettings'] is Map<String, dynamic>) {
        final settings = data['inactivitySettings'] as Map<String, dynamic>;
        if (settings.containsKey('thresholdHours')) {
          return settings['thresholdHours'] as int;
        }
      }

      // Return default threshold if not found
      return 24; // 24 hours default
    } catch (e) {
      print('❌ Error getting inactivity threshold from Firestore: $e');
      return 24; // Default fallback
    }
  }

  // Sync local settings with Firestore
  static Future<void> syncLocalSettingsToFirestore(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Get settings from shared preferences
      final startHourStr = prefs.getString('startHour') ?? '08:00';
      final endHourStr = prefs.getString('endHour') ?? '20:00';

      // Save to Firestore
      await saveActiveHours(
        uid: uid,
        startHour: startHourStr,
        endHour: endHourStr,
      );
    } catch (e) {
      print('❌ Error syncing local settings to Firestore: $e');
    }
  }
}
