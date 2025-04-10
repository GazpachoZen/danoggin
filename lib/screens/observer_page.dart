import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:danoggin/services/notification_service.dart';
import 'package:danoggin/models/user_role.dart';
import 'package:intl/intl.dart';
import 'package:danoggin/screens/settings_page.dart';
import 'package:danoggin/screens/quiz_page.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:timeago/timeago.dart' as timeago;

class ObserverPage extends StatefulWidget {
  const ObserverPage({super.key});

  @override
  State<ObserverPage> createState() => _ObserverPageState();
}

class _ObserverPageState extends State<ObserverPage> {
  Timer? _pollingTimer;
  final Duration pollInterval = Duration(minutes: 2);
  String? lastAcknowledgedId;
  String? lastNotifiedId;

  @override
  void initState() {
    super.initState();
    _loadLastAcknowledged();
    _startPollingLoop();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadLastAcknowledged() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      lastAcknowledgedId = prefs.getString('lastAcknowledgedCheckInId');
    });
  }

  Future<void> _acknowledge(String docId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lastAcknowledgedCheckInId', docId);
    setState(() {
      lastAcknowledgedId = docId;
    });
  }

  // void _startPollingLoop() {
  //   print("JEI: _startPollingLoop with pollInterval=$pollInterval");
  //   _pollingTimer =
  //       Timer.periodic(pollInterval, (_) => _checkResponderStatus());
  // }

  Future<void> _startPollingLoop() async {
    final prefs = await SharedPreferences.getInstance();
    final interval = prefs.getDouble('observerPollInterval') ?? 2;
    final duration = Duration(minutes: interval.round());

    _pollingTimer?.cancel();
    print("JEI: _startPollingLoop with duration=$duration");
    _pollingTimer = Timer.periodic(duration, (_) => _checkResponderStatus());
  }

  Future<void> _checkResponderStatus() async {
    const responderId = 'responder';

    final snapshot = await FirebaseFirestore.instance
        .collection('responder_status')
        .doc(responderId)
        .collection('check_ins')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .get();

    final now = DateTime.now();
    print(
        "JEI: DING-DING-DING... _checkResponderStatus @ ${now.hour}:${now.minute}:${now.second}");

    if (snapshot.docs.isNotEmpty) {
      final doc = snapshot.docs.first;
      final data = doc.data();
      final result = data['result'];
      final timestamp = DateTime.tryParse(data['timestamp']);
      final mostRecentTimeStr = timestamp != null
          ? DateFormat('M/d h:mma').format(timestamp).toLowerCase()
          : 'Unknown time';
      final docId = doc.id;
      print(
          "JEI: result=$result, docId=$docId, lastAcknowledgedId=$lastAcknowledgedId, lastNotifiedId=$lastNotifiedId");
      if ((result == 'missed' || result == 'incorrect') &&
          docId != lastAcknowledgedId) {
        print("JEI: Trying to show a notification");
        await NotificationService.showBasicNotification(
          id: 2,
          title: 'Danoggin Alert',
          body: 'Check-in at $mostRecentTimeStr was $result.',
        );
        lastNotifiedId = docId;
      }
    }
  }

  Widget _buildCheckInList() {
    const responderId = 'responder';

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('responder_status')
          .doc(responderId)
          .collection('check_ins')
          .orderBy('timestamp', descending: true)
          .limit(10)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const CircularProgressIndicator();

        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return const Text('No check-ins found.');

        final latest = docs.first;
        final latestId = latest.id;
        final latestData = latest.data() as Map<String, dynamic>;
        final latestResult = latestData['result'];
        final needsAck =
            (latestResult == 'missed' || latestResult == 'incorrect') &&
                latestId != lastAcknowledgedId;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (needsAck)
              Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.check),
                  label: const Text('Acknowledge Issue'),
                  onPressed: () => _acknowledge(latestId),
                ),
              ),
            for (final doc in docs)
              _buildCheckInTile(doc.id, doc.data() as Map<String, dynamic>),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Observer Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () async {
              final newRole = await Navigator.push<UserRole>(
                context,
                MaterialPageRoute(
                  builder: (_) => SettingsPage(currentRole: UserRole.observer),
                ),
              );

              if (newRole != null && newRole != UserRole.observer) {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('userRole', newRole.name);
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => newRole == UserRole.responder
                        ? QuizPage()
                        : ObserverPage(),
                  ),
                );
              }
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: _buildCheckInList(),
      ),
    );
  }
}
