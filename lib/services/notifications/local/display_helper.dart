import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart' as audio;
import 'package:danoggin/utils/logger.dart';

/// Helper for displaying in-app notifications
class DisplayHelper {
  final Logger _logger = Logger();

  /// Show enhanced in-app notification
  Future<void> showEnhancedInAppNotification(
    BuildContext context,
    String title,
    String body, {
    bool playSound = true,
  }) async {
    _logger.i("Showing in-app notification: $title");

    // Play notification sound
    if (playSound) {
      try {
        final player = audio.AudioPlayer();
        await player.play(audio.AssetSource('sounds/notification_sound.mp3'));
      } catch (e) {
        _logger.i("Error playing notification sound: $e");
      }
    }

    // Define overlay entry
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 10,
        left: 10,
        right: 10,
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue[100],
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.blue[700]!, width: 2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(Icons.notification_important, color: Colors.blue[700]),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.blue[900],
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Text(
                  body,
                  style: TextStyle(fontSize: 14),
                ),
                SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    child: Text('DISMISS'),
                    onPressed: () {
                      entry.remove();
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // Insert the overlay
    Overlay.of(context).insert(entry);

    // Remove after a delay
    Future.delayed(Duration(seconds: 8), () {
      try {
        if (entry.mounted) {
          // Add this check
          entry.remove();
        }
      } catch (e) {
        _logger.i("Error removing notification overlay: $e");
      }
    });
  }
}
