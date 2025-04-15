
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:timeago/timeago.dart' as timeago;

class CheckInHistoryWidget extends StatelessWidget {
  final String responderId; // This is now expected to be a Firebase UID
  final int limit;

  const CheckInHistoryWidget({
    Key? key,
    required this.responderId,
    this.limit = 10,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('responder_status')
          .doc(responderId) // Use the actual UID
          .collection('check_ins')
          .orderBy('timestamp', descending: true)
          .limit(limit)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Text('No check-in records found.');
        }

        final entries = snapshot.data!.docs;

        return ListView.separated(
          shrinkWrap: true,
          itemCount: entries.length,
          separatorBuilder: (_, __) => const Divider(),
          itemBuilder: (context, index) {
            final data = entries[index].data() as Map<String, dynamic>;
            final timestampStr = data['timestamp'] ?? '';
            final prompt = data['prompt'] ?? '';
            final result = data['result'] ?? 'unknown';

            final timestamp = DateTime.tryParse(timestampStr);
            final formattedTime = timestamp != null
                ? DateFormat.yMMMd().add_jm().format(timestamp)
                : 'Unknown time';

            final relativeTime = timestamp != null
                ? timeago.format(timestamp)
                : '';

            final color = switch (result) {
              'correct' => Colors.green,
              'incorrect' => Colors.red,
              'missed' => Colors.orange,
              _ => Colors.grey,
            };

            return ListTile(
              leading: Icon(Icons.check_circle, color: color),
              title: Text(prompt),
              subtitle: Text('$formattedTime  •  $relativeTime'),
              trailing: Text(result.toUpperCase(), style: TextStyle(color: color)),
            );
          },
        );
      },
    );
  }
}
