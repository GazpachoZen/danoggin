import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:flutter/material.dart';

class TimezoneHelper {
  static bool _initialized = false;
  
  // Initialize time zone database
  static Future<void> initialize() async {
    if (!_initialized) {
      tz_data.initializeTimeZones();
      _initialized = true;
    }
  }
  
  // Get the current local time zone
  static String getCurrentTimeZone() {
    try {
      // Initialize if needed
      if (!_initialized) {
        tz_data.initializeTimeZones();
        _initialized = true;
      }
      
      // Get local time zone
      final detroit = tz.getLocation('America/Detroit');
      final now = tz.TZDateTime.now(detroit);
      return now.location.name;
    } catch (e) {
      print('❌ Error getting time zone: $e');
      return 'UTC'; // Default fallback
    }
  }
  
  // Convert time from one time zone to another
  static TimeOfDay convertTimeOfDay(TimeOfDay time, String fromTimeZone, String toTimeZone) {
    try {
      // Initialize if needed
      if (!_initialized) {
        tz_data.initializeTimeZones();
        _initialized = true;
      }
      
      // Create a DateTime for today with the given time in the source time zone
      final now = DateTime.now();
      final fromLocation = tz.getLocation(fromTimeZone);
      final sourceDateTime = tz.TZDateTime(
          fromLocation,
          now.year,
          now.month,
          now.day,
          time.hour,
          time.minute);
      
      // Convert to target time zone
      final toLocation = tz.getLocation(toTimeZone);
      final targetDateTime = tz.TZDateTime.from(sourceDateTime, toLocation);
      
      // Return as TimeOfDay
      return TimeOfDay(hour: targetDateTime.hour, minute: targetDateTime.minute);
    } catch (e) {
      print('❌ Error converting time zones: $e');
      // Return original time if conversion fails
      return time;
    }
  }
  
  // Check if current time is within active hours
  static bool isWithinActiveHours(TimeOfDay current, TimeOfDay start, TimeOfDay end) {
    // Convert to minutes since midnight for easier comparison
    final currentMinutes = current.hour * 60 + current.minute;
    final startMinutes = start.hour * 60 + start.minute;
    final endMinutes = end.hour * 60 + end.minute;
    
    // Handle normal case (start time is before end time)
    if (startMinutes <= endMinutes) {
      return currentMinutes >= startMinutes && currentMinutes <= endMinutes;
    } 
    // Handle overnight case (end time is on the next day)
    else {
      return currentMinutes >= startMinutes || currentMinutes <= endMinutes;
    }
  }
}
