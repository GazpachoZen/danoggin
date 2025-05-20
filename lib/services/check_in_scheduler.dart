import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:danoggin/services/auth_service.dart';
import 'package:danoggin/utils/timezone_helper.dart';

/// Service for calculating and managing responder check-in schedules
class CheckInScheduler {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  /// Calculate the next check-in time based on user settings and current time
  /// @param intervalMinutes - Minutes between check-ins
  /// @param activeStartHour - Start of active hours (24-hour format)
  /// @param activeEndHour - End of active hours (24-hour format)
  /// @param timeZone - User's timezone (e.g., "America/Detroit")
  /// @param lastCheckInTime - Optional last check-in time, defaults to now
  /// @return DateTime of next scheduled check-in in UTC
  static DateTime calculateNextCheckInTime({
    required int intervalMinutes,
    required TimeOfDay activeStartHour,
    required TimeOfDay activeEndHour,
    required String timeZone,
    DateTime? lastCheckInTime,
  }) {
    // Use provided time or current time as base
    final baseTime = lastCheckInTime ?? DateTime.now();
    
    // Add the interval to the base time
    DateTime nextTime = baseTime.add(Duration(minutes: intervalMinutes));
    
    // Convert to user's timezone for active hours checking
    try {
      // Note: For now, we'll use simple logic since timezone conversion is complex
      // In a production app, you'd want to use a proper timezone library
      final currentHour = nextTime.hour;
      final currentMinute = nextTime.minute;
      final currentTimeOfDay = TimeOfDay(hour: currentHour, minute: currentMinute);
      
      // Check if next time falls within active hours
      if (_isWithinActiveHours(currentTimeOfDay, activeStartHour, activeEndHour)) {
        // Next time is within active hours, use it as-is
        return nextTime;
      } else {
        // Next time is outside active hours, schedule for next active start
        return _scheduleForNextActiveStart(nextTime, activeStartHour);
      }
    } catch (e) {
      print('❌ Error in timezone calculation: $e');
      // Fallback: just add interval
      return nextTime;
    }
  }
  
  /// Check if a given time falls within active hours
  static bool _isWithinActiveHours(
    TimeOfDay current,
    TimeOfDay start,
    TimeOfDay end,
  ) {
    final currentMinutes = current.hour * 60 + current.minute;
    final startMinutes = start.hour * 60 + start.minute;
    final endMinutes = end.hour * 60 + end.minute;
    
    // Handle normal case (start < end)
    if (startMinutes <= endMinutes) {
      return currentMinutes >= startMinutes && currentMinutes <= endMinutes;
    }
    // Handle overnight case (end < start, like 22:00 to 06:00)
    else {
      return currentMinutes >= startMinutes || currentMinutes <= endMinutes;
    }
  }
  
  /// Schedule the next check-in for the start of the next active period
  static DateTime _scheduleForNextActiveStart(
    DateTime baseTime,
    TimeOfDay activeStart,
  ) {
    // Create a DateTime for today at the active start time
    DateTime todayActiveStart = DateTime(
      baseTime.year,
      baseTime.month,
      baseTime.day,
      activeStart.hour,
      activeStart.minute,
    );
    
    // If today's active start has passed, schedule for tomorrow
    if (todayActiveStart.isBefore(baseTime)) {
      todayActiveStart = todayActiveStart.add(Duration(days: 1));
    }
    
    return todayActiveStart;
  }
  
  /// Update the user's next check-in time in Firestore
  /// This is called after completing a check-in or changing settings
  static Future<void> updateNextCheckInTime({
    required int intervalMinutes,
    required TimeOfDay activeStartHour,
    required TimeOfDay activeEndHour,
    required String timeZone,
    DateTime? lastCheckInTime,
  }) async {
    try {
      final uid = AuthService.currentUserId;
      
      // Calculate next check-in time
      final nextCheckInTime = calculateNextCheckInTime(
        intervalMinutes: intervalMinutes,
        activeStartHour: activeStartHour,
        activeEndHour: activeEndHour,
        timeZone: timeZone,
        lastCheckInTime: lastCheckInTime,
      );
      
      // Update Firestore with the new schedule
      await _firestore.collection('users').doc(uid).set({
        'checkInSettings': {
          'intervalMinutes': intervalMinutes,
          'nextCheckInTime': Timestamp.fromDate(nextCheckInTime),
          'lastCheckInTime': lastCheckInTime != null 
              ? Timestamp.fromDate(lastCheckInTime) 
              : FieldValue.serverTimestamp(),
          'lastUpdated': FieldValue.serverTimestamp(),
          'enabled': true,
        }
      }, SetOptions(merge: true));
      
      print('CheckInScheduler: Next check-in scheduled for ${nextCheckInTime.toIso8601String()}');
    } catch (e) {
      print('❌ Error updating next check-in time: $e');
      rethrow;
    }
  }
  
  /// Update just the last check-in time (called after completing a check-in)
  /// This will automatically calculate and set the next check-in time
  static Future<void> updateAfterCheckIn() async {
    try {
      final uid = AuthService.currentUserId;
      final now = DateTime.now();
      
      // Get current user settings
      final userDoc = await _firestore.collection('users').doc(uid).get();
      if (!userDoc.exists) {
        throw Exception('User document not found');
      }
      
      final userData = userDoc.data() as Map<String, dynamic>;
      
      // Extract settings from SharedPreferences (since that's where they're stored)
      final prefs = await SharedPreferences.getInstance();
      final intervalMinutes = (prefs.getDouble('alertFrequency') ?? 5).round();
      final startHourStr = prefs.getString('startHour') ?? '08:00';
      final endHourStr = prefs.getString('endHour') ?? '20:00';
      
      // Parse active hours
      final activeStartHour = _parseTimeOfDay(startHourStr);
      final activeEndHour = _parseTimeOfDay(endHourStr);
      
      // Get timezone from Firestore or default
      final activeHours = userData['activeHours'] as Map<String, dynamic>?;
      final timeZone = activeHours?['timeZone'] as String? ?? 'UTC';
      
      // Update with current check-in time
      await updateNextCheckInTime(
        intervalMinutes: intervalMinutes,
        activeStartHour: activeStartHour,
        activeEndHour: activeEndHour,
        timeZone: timeZone,
        lastCheckInTime: now,
      );
      
    } catch (e) {
      print('❌ Error updating schedule after check-in: $e');
      rethrow;
    }
  }
  
  /// Update schedule when user changes settings (without completing check-in)
  static Future<void> updateAfterSettingsChange({
    required int intervalMinutes,
    required TimeOfDay activeStartHour,
    required TimeOfDay activeEndHour,
    required String timeZone,
  }) async {
    try {
      // Calculate next time based on current time (no last check-in)
      await updateNextCheckInTime(
        intervalMinutes: intervalMinutes,
        activeStartHour: activeStartHour,
        activeEndHour: activeEndHour,
        timeZone: timeZone,
        lastCheckInTime: null, // Use current time as base
      );
    } catch (e) {
      print('❌ Error updating schedule after settings change: $e');
      rethrow;
    }
  }
  
  /// Parse a time string (HH:MM) into TimeOfDay
  static TimeOfDay _parseTimeOfDay(String timeStr) {
    try {
      final parts = timeStr.split(':');
      return TimeOfDay(
        hour: int.parse(parts[0]),
        minute: int.parse(parts[1]),
      );
    } catch (e) {
      print('❌ Error parsing time string "$timeStr": $e');
      // Return default time
      return TimeOfDay(hour: 8, minute: 0);
    }
  }
  
  /// Get the next scheduled check-in time for current user
  static Future<DateTime?> getNextCheckInTime() async {
    try {
      final uid = AuthService.currentUserId;
      final userDoc = await _firestore.collection('users').doc(uid).get();
      
      if (!userDoc.exists) return null;
      
      final userData = userDoc.data() as Map<String, dynamic>;
      final checkInSettings = userData['checkInSettings'] as Map<String, dynamic>?;
      
      if (checkInSettings == null) return null;
      
      final nextCheckInTimestamp = checkInSettings['nextCheckInTime'] as Timestamp?;
      return nextCheckInTimestamp?.toDate();
    } catch (e) {
      print('❌ Error getting next check-in time: $e');
      return null;
    }
  }
  
  /// Check if a check-in is currently due (within the timeout window)
  static Future<bool> isCheckInDue() async {
    try {
      final nextCheckInTime = await getNextCheckInTime();
      if (nextCheckInTime == null) return false;
      
      final now = DateTime.now();
      
      // Check-in is due if:
      // 1. The scheduled time has passed
      // 2. We're still within the timeout window
      
      // Get timeout from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final timeoutMinutes = (prefs.getDouble('timeoutDuration') ?? 1);
      
      final timeoutWindow = Duration(minutes: timeoutMinutes.round());
      final dueTime = nextCheckInTime;
      final expireTime = nextCheckInTime.add(timeoutWindow);
      
      return now.isAfter(dueTime) && now.isBefore(expireTime);
    } catch (e) {
      print('❌ Error checking if check-in is due: $e');
      return false;
    }
  }
}