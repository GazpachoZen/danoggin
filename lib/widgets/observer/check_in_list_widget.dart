import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:timeago/timeago.dart' as timeago;

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
      return const Center(
        child: Text('No responders linked yet. Add a responder to monitor.'),
      );
    }

    if (selectedResponderUid == null) {
      return const Center(
        child: Text('No responder selected'),
      );
    }

    final responderName = responderMap[selectedResponderUid] ?? 'Unknown';

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
                  onPressed: () => onAcknowledge(latestKey),
                ),
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

  Widget _buildCheckInTile(String id, Map<String, dynamic> data) {
    final result = data['result'];
    final timestampStr = data['timestamp'] ?? '';
    final prompt = data['prompt'] ?? 'Unknown prompt';

    final timestamp = DateTime.tryParse(timestampStr);
    final absolute = timestamp != null
        ? DateFormat('M/d h:mma').format(timestamp).toLowerCase()
        : 'Unknown time';
    final relative = timestamp != null ? timeago.format(timestamp) : '';

    final color = switch (result) {
      'correct' => Colors.green,
      'incorrect' => Colors.red,
      'missed' => Colors.orange,
      _ => Colors.grey,
    };

    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(vertical: -3),
      leading: Icon(Icons.circle, color: color, size: 12),
      title: Text(prompt, style: const TextStyle(fontSize: 14)),
      subtitle:
          Text('$absolute • $relative', style: const TextStyle(fontSize: 12)),
      trailing: Text(result.toUpperCase(),
          style: TextStyle(color: color, fontSize: 13)),
    );
  }
}