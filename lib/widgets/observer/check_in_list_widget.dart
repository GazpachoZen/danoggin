import 'package:danoggin/models/user_role.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:danoggin/services/notifications/notification_manager.dart';
import 'package:danoggin/utils/logger.dart';

class CheckInListWidget extends StatelessWidget {
  final Map<String, String> responderMap;
  final String? selectedResponderUid;
  final String? lastAcknowledgedId;
  final Function(String) onAcknowledge;

  const CheckInListWidget({
    Key? key,
    required this.responderMap,
    required this.selectedResponderUid,
    required this.lastAcknowledgedId,
    required this.onAcknowledge,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (responderMap.isEmpty) {
      return Center(
        child: Text(
          'No ${UserRole.responder.displayLabelPlural} linked yet. Add somebody to monitor.',
          style: const TextStyle(
            fontSize: 44.0, // Increased from default
            color: Colors.black87,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }

    if (selectedResponderUid == null) {
      return const Center(
        child: Text('No responder selected'),
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('responder_status')
          .doc(selectedResponderUid)
          .collection('check_ins')
          .orderBy('timestamp', descending: true)
          .limit(10)
          .snapshots(),
      builder: (context, checkInSnapshot) {
        if (!checkInSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = checkInSnapshot.data!.docs;

        if (docs.isEmpty) {
          return const Center(child: Text('No check-ins found.'));
        }

        final latest = docs.first;
        final latestId = latest.id;
        final latestData = latest.data() as Map<String, dynamic>;
        final latestResult = latestData['result'];

        // Use a combined key of responderUid:checkInId for acknowledgements
        final latestKey = "$selectedResponderUid:$latestId";
        final needsAck =
            (latestResult == 'missed' || latestResult == 'incorrect') &&
                latestKey != lastAcknowledgedId;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (needsAck)
              Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: ElevatedButton.icon(
                    icon: const Icon(Icons.check),
                    label: const Text('Acknowledge Issue'),
                    onPressed: () async {
                      try {
                        Logger().i('Observer: Acknowledging issue - clearing all badges and notifications');
                        
                        // Clear all badges and notifications when acknowledging
                        await _clearAllNotifications();
                        
                        // Then call the acknowledgment callback
                        onAcknowledge(latestKey);
                        
                        Logger().i('Observer: Issue acknowledged and notifications cleared');
                      } catch (e) {
                        Logger().e('Observer: Error during acknowledgment: $e');
                        // Still proceed with acknowledgment even if clearing fails
                        onAcknowledge(latestKey);
                      }
                    }),
              ),
            Expanded(
              child: ListView.builder(
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final doc = docs[index];
                  return _buildCheckInTile(
                      doc.id, doc.data() as Map<String, dynamic>);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  /// Clear all badges and notifications for observers
  Future<void> _clearAllNotifications() async {
    try {
      await NotificationManager().clearIOSBadge();
      await NotificationManager().cancelAllNotifications();
      Logger().i('CheckInListWidget: Cleared all badges and notifications');
    } catch (e) {
      Logger().e('CheckInListWidget: Error clearing notifications: $e');
      rethrow; // Let caller handle the error
    }
  }

  Widget _buildCheckInTile(String id, Map<String, dynamic> data) {
    final result = data['result'];
    final timestampStr = data['timestamp'] ?? '';
    final prompt = data['prompt'] ?? 'Unknown prompt';

    final timestamp = DateTime.tryParse(timestampStr);
    final absolute = timestamp != null
        ? DateFormat('M/d h:mma').format(timestamp).toLowerCase()
        : 'Unknown time';
    final relative = timestamp != null ? timeago.format(timestamp) : '';

    Widget getResultIcon(String result) {
      switch (result) {
        case 'correct':
          return Icon(Icons.check_circle, color: Colors.green, size: 18);
        case 'incorrect_first_attempt':
          return Icon(Icons.cancel, color: Colors.grey, size: 18);
        case 'incorrect':
          return Icon(Icons.cancel, color: Colors.red, size: 18);
        case 'missed':
          return Icon(Icons.schedule, color: Colors.orange, size: 18);
        case 'missed_retry':
          return Icon(Icons.timer_off, color: Colors.red[700], size: 18);
        default:
          return Icon(Icons.help_outline, color: Colors.grey, size: 18);
      }
    }

    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(vertical: -3),
      leading: getResultIcon(result),
      title: Text(prompt, style: const TextStyle(fontSize: 14)),
      subtitle:
          Text('$absolute • $relative', style: const TextStyle(fontSize: 12)),
    );
  }
}