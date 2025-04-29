import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:danoggin/services/notification_service.dart';
import 'package:danoggin/models/user_role.dart';
import 'package:intl/intl.dart';
import 'package:danoggin/screens/settings_page.dart';
import 'package:danoggin/screens/quiz_page.dart';
import 'package:danoggin/services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:danoggin/services/notification_helper.dart';
import 'package:danoggin/utils/back_button_handler.dart';

Future<void> requestNotificationPermissions() async {
  // Request permission for notifications
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // For Android, there's no explicit permissions request in this version
  // The channel creation handles this automatically

  // For iOS we would request permissions, but since you're on Android, this is less relevant

  print("Notification permission handled through channel creation");
}

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

  // Add state for responder selection
  String? _selectedResponderUid;
  Map<String, String> _responderMap = {}; // Map of responder UIDs to names

  List<QueryDocumentSnapshot> _currentCheckIns = [];
  Timer? _dataRefreshTimer;

  // Add back button handler
  final BackButtonHandler _backButtonHandler = BackButtonHandler();

  @override
  void initState() {
    super.initState();
    // Request notification permissions on startup
    requestNotificationPermissions();
    _loadLastAcknowledged();
    _loadResponders(); // Add this to load responders on startup
    _startPollingLoop();
    _startDataRefreshTimer();
  }

  // Add method to load responders
  Future<void> _loadResponders() async {
    try {
      final observerUid = AuthService.currentUserId;
      final observerDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(observerUid)
          .get();

      final userData = observerDoc.data() as Map<String, dynamic>?;
      final observingMap =
          userData?['observing'] as Map<String, dynamic>? ?? {};

      setState(() {
        _responderMap = Map<String, String>.from(observingMap);
        // Select the first responder by default if we haven't selected one yet
        if (_selectedResponderUid == null && _responderMap.isNotEmpty) {
          _selectedResponderUid = _responderMap.keys.first;
        } else if (_responderMap.isEmpty) {
          // Clear selection if no responders are available
          _selectedResponderUid = null;
        } else if (_selectedResponderUid != null &&
            !_responderMap.containsKey(_selectedResponderUid)) {
          // If current selection is no longer valid, reset to first available
          _selectedResponderUid = _responderMap.keys.first;
        }
      });
    } catch (e) {
      print('Error loading responders: $e');
    }
  }

  // Add method to change selected responder
  void _selectResponder(String responderUid) {
    setState(() {
      _selectedResponderUid = responderUid;
    });
  }

  void _startDataRefreshTimer() async {
    // Refresh every 1 minute (adjust as needed)
    const refreshDuration = Duration(minutes: 1);
    _dataRefreshTimer?.cancel();
    _dataRefreshTimer = Timer.periodic(refreshDuration, (_) {
      if (mounted) {
        _loadResponders(); // Refresh responder list periodically
        setState(() {
          // This will trigger a rebuild of the UI
        });
      }
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _dataRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadLastAcknowledged() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      lastAcknowledgedId = prefs.getString('lastAcknowledgedCheckInId');
    });
  }

  Future<void> _acknowledge(String compositeKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lastAcknowledgedCheckInId', compositeKey);
    setState(() {
      lastAcknowledgedId = compositeKey;
    });
  }

  Future<void> _startPollingLoop() async {
    final prefs = await SharedPreferences.getInstance();
    final interval = prefs.getDouble('observerPollInterval') ?? 2;
    final duration = Duration(minutes: interval.round());

    _pollingTimer?.cancel();
    print("JEI: _startPollingLoop with duration=$duration");
    _pollingTimer = Timer.periodic(duration, (_) => _checkResponderStatus());
  }

  Future<void> _checkResponderStatus() async {
    try {
      // Get the responder UIDs that this observer is linked to
      final observerUid = AuthService.currentUserId;
      final observerDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(observerUid)
          .get();

      final userData = observerDoc.data() as Map<String, dynamic>?;
      final observingMap =
          userData?['observing'] as Map<String, dynamic>? ?? {};
      final responderUids = observingMap.keys.toList();

      if (responderUids.isEmpty) {
        print("No linked responders found");
        return;
      }

      // Track notifications sent in this polling cycle to avoid duplicates
      List<String> notifiedInThisCycle = [];

      // Check each linked responder
      for (final responderUid in responderUids) {
        final responderName = observingMap[responderUid];

        // Use get() to force a fresh read from Firestore
        final snapshot = await FirebaseFirestore.instance
            .collection('responder_status')
            .doc(responderUid)
            .collection('check_ins')
            .orderBy('timestamp', descending: true)
            .limit(1)
            .get();

        final now = DateTime.now();
        print(
            "Checking responder $responderName ($responderUid) @ ${now.hour}:${now.minute}:${now.second}");

        if (snapshot.docs.isEmpty) continue;

        final doc = snapshot.docs.first;
        final data = doc.data();
        final result = data['result'] as String;
        final timestamp = DateTime.tryParse(data['timestamp'] as String);
        final docId = doc.id;

        // Skip if we can't parse the timestamp
        if (timestamp == null) continue;

        final checkInAge = now.difference(timestamp);
        final mostRecentTimeStr =
            DateFormat('M/d h:mma').format(timestamp).toLowerCase();

        print(
            "Found check-in: id=$docId, result=$result, age=${checkInAge.inMinutes}m");

        // Create a unique identifier for this check-in
        final checkInKey = "$responderUid:$docId";

        // Only notify for recent check-ins that are missed or incorrect
        if ((result == 'missed' || result == 'incorrect') &&
            checkInAge.inHours < 24) {
          // Only consider relatively recent check-ins (last 24h)

          // Check if we've already acknowledged this issue
          final isAcknowledged = checkInKey == lastAcknowledgedId;

          // Check if we've already notified about this issue in this polling cycle
          final alreadyNotifiedThisCycle =
              notifiedInThisCycle.contains(checkInKey);

          if (!isAcknowledged && !alreadyNotifiedThisCycle) {
            print("Issue detected: $responderName had a $result check-in");

            // Mark this as notified in this cycle to avoid duplicate notifications
            notifiedInThisCycle.add(checkInKey);

            // Update tracking of last notification - this is only to track the
            // very last notification sent, not to prevent repeated notifications
            setState(() {
              lastNotifiedId = checkInKey;
            });

            // Save to persistent storage
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('lastNotifiedId', checkInKey);

            // Show notification
            await NotificationHelper.showAlert(
              id: responderUid.hashCode.abs(),
              title: 'Danoggin Alert',
              body:
                  '$responderName had a $result check-in at $mostRecentTimeStr',
            );

            print("Notification sent for $responderName's $result check-in");
          }
        }
      }
    } catch (e) {
      print("Error in _checkResponderStatus: $e");
    }
  }

  Future<void> _testNotifications() async {
    try {
      // Try to check if notifications are enabled
      bool enabled = true;
      try {
        enabled = await NotificationHelper.areNotificationsEnabled();
      } catch (e) {
        print('Error checking notification permissions: $e');
        // If we can't check, assume they're enabled
      }

      if (!enabled) {
        // Show manual instructions if notifications are disabled
        NotificationHelper.openNotificationSettings(context);
        return;
      }

      // Test notification
      await NotificationHelper.testNotification();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Test notification sent!'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      print('Error testing notifications: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error sending test notification: $e'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  // New method to build the responder selector
  Widget _buildResponderSelector() {
    if (_responderMap.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: EdgeInsets.only(bottom: 16.0),
      child: Padding(
        padding: EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Select Responder:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            SizedBox(height: 8),
            Container(
              width: double.infinity,
              child: Wrap(
                spacing: 8.0,
                runSpacing: 8.0,
                children: _responderMap.entries.map((entry) {
                  final isSelected = entry.key == _selectedResponderUid;
                  return ChoiceChip(
                    label: Text(entry.value),
                    selected: isSelected,
                    onSelected: (_) => _selectResponder(entry.key),
                    backgroundColor: Colors.grey[200],
                    selectedColor: Colors.deepPurple[100],
                    labelStyle: TextStyle(
                      color:
                          isSelected ? Colors.deepPurple[800] : Colors.black87,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Modified to build check-in list for a specific responder
  Widget _buildCheckInList() {
    if (_responderMap.isEmpty) {
      return const Center(
        child: Text('No responders linked yet. Add a responder to monitor.'),
      );
    }

    if (_selectedResponderUid == null) {
      return const Center(
        child: Text('No responder selected'),
      );
    }

    final responderName = _responderMap[_selectedResponderUid] ?? 'Unknown';

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('responder_status')
          .doc(_selectedResponderUid)
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
        final latestKey = "$_selectedResponderUid:$latestId";
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
                  onPressed: () => _acknowledge(latestKey),
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

  @override
  Widget build(BuildContext context) {
    // Add WillPopScope to handle back button press
    return WillPopScope(
      onWillPop: () =>
          _backButtonHandler.handleBackPress(context, UserRole.observer),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Observer Dashboard'),
          actions: [
            IconButton(
              icon: const Icon(Icons.notifications),
              tooltip: 'Test Notifications',
              onPressed: _testNotifications,
            ),
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () async {
                final result = await Navigator.push<dynamic>(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        SettingsPage(currentRole: UserRole.observer),
                  ),
                );

                // If result is a Boolean 'true', relationships have changed
                if (result == true) {
                  await _loadResponders(); // Refresh the responder list
                  setState(() {}); // Update the UI
                }
                // If result is a UserRole, handle role change as before
                else if (result != null && result != UserRole.observer) {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('userRole', result.name);
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (_) => result == UserRole.responder
                          ? QuizPage(
                              currentRole: result) // Pass the role parameter
                          : ObserverPage(),
                    ),
                  );
                }
              },
            ),
          ],
        ),
        body: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height -
                AppBar().preferredSize.height -
                MediaQuery.of(context).padding.top,
          ),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Responder selector
              if (_responderMap.length > 1) _buildResponderSelector(),

              // Selected responder info
              if (_selectedResponderUid != null && _responderMap.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Text(
                    'Monitoring: ${_responderMap[_selectedResponderUid] ?? "Unknown"}',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),

              // Check-in list
              Expanded(
                child: _buildCheckInList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _triggerCheckInNotification({
    required String responderUid,
    required String responderName,
    required String result,
    required String timeStr,
    required String checkInId,
  }) async {
    try {
      // Create a unique key for this check-in
      final checkInKey = "$responderUid:$checkInId";

      // Check if we've already notified for this
      if (checkInKey == lastNotifiedId || checkInKey == lastAcknowledgedId) {
        print("Already notified or acknowledged for check-in: $checkInKey");
        return;
      }

      print("🔔 Preparing to send notification for $responderName");

      // First update our state to prevent duplicate notifications
      setState(() {
        lastNotifiedId = checkInKey;
      });

      // Use direct notification method for more reliable delivery
      const AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
        'danoggin_alerts', // different channel ID
        'Danoggin Urgent Alerts',
        channelDescription:
            'Used for critical alerts about missed or incorrect check-ins',
        importance: Importance.high,
        priority: Priority.high,
        enableVibration: true,
        playSound: true,
        icon: 'ic_stat_warning',
      );

      const NotificationDetails platformDetails =
          NotificationDetails(android: androidDetails);

      // Generate a unique notification ID based on the check-in
      final notificationId = checkInId.hashCode.abs();

      print("🔔 Sending notification with ID: $notificationId");

      // Use the plugin directly
      final FlutterLocalNotificationsPlugin notifications =
          FlutterLocalNotificationsPlugin();

      await notifications.show(
        notificationId,
        'Danoggin Alert: $result',
        '$responderName had a $result check-in at $timeStr',
        platformDetails,
      );

      print("🔔 Notification sent successfully!");

      // Save the notification in a local database for persistence
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('lastNotifiedId', checkInKey);

      // Also show a snackbar in the UI
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Notification sent for $responderName'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e, stackTrace) {
      print("❌ Error sending notification: $e");
      print(stackTrace);

      // Show error in UI
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Notification error: $e'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }
}

Future<void> testDirectNotification() async {
  try {
    print("Testing direct notification...");

    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'danoggin_direct_test', // Channel ID
      'Danoggin Test Channel', // Channel name
      channelDescription: 'Channel for testing notifications',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'ticker',
    );

    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    // Generate a unique ID
    final int notificationId = DateTime.now().millisecond;

    await FlutterLocalNotificationsPlugin().show(
      notificationId,
      'Plain Test Notification',
      'This is a simple notification from Danoggin',
      platformChannelSpecifics,
    );

    print("Direct test notification sent!");
  } catch (e) {
    print("Error sending direct test notification: $e");
  }
}

// Add this to both the observer and responder initialization code
void initNotifications() {
  // Initialize notification plugin
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initializationSettings =
      InitializationSettings(android: initializationSettingsAndroid);

  FlutterLocalNotificationsPlugin().initialize(
    initializationSettings,
    onDidReceiveNotificationResponse: (NotificationResponse details) {
      print("Notification clicked: ${details.id}");
    },
  );

  print("Notifications initialized");
}
