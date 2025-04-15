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
  String? _currentResponderUid;
  String? _responderName;
  List<QueryDocumentSnapshot> _currentCheckIns = [];
  Timer? _dataRefreshTimer;

@override
void initState() {
  super.initState();
  // Request notification permissions on startup
  requestNotificationPermissions();
  _loadLastAcknowledged();
  _startPollingLoop();
}

void _startDataRefreshTimer() async {
  // Refresh every 1 minute (adjust as needed)
  const refreshDuration = Duration(minutes: 1);
  _dataRefreshTimer?.cancel();
  _dataRefreshTimer = Timer.periodic(refreshDuration, (_) {
    if (mounted) {
      setState(() {
        // This will trigger a rebuild of the UI
        // The StatefulBuilder in _buildCheckInList will then re-fetch data
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
    final observingMap = userData?['observing'] as Map<String, dynamic>? ?? {};
    final responderUids = observingMap.keys.toList();
    
    if (responderUids.isEmpty) {
      print("No linked responders found");
      return;
    }
    
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
      print("Checking responder $responderName ($responderUid) @ ${now.hour}:${now.minute}:${now.second}");
  
      if (snapshot.docs.isEmpty) continue;
      
      final doc = snapshot.docs.first;
      final data = doc.data();
      final result = data['result'] as String;
      final timestamp = DateTime.tryParse(data['timestamp'] as String);
      final docId = doc.id;
      
      // Skip if we can't parse the timestamp
      if (timestamp == null) continue;
      
      final checkInAge = now.difference(timestamp);
      final mostRecentTimeStr = DateFormat('M/d h:mma').format(timestamp).toLowerCase();
      
      print("Found check-in: id=$docId, result=$result, age=${checkInAge.inMinutes}m");
      
      // Create a unique identifier for this check-in
      final checkInKey = "$responderUid:$docId";
      
      // Only notify for recent check-ins that are missed or incorrect
      if ((result == 'missed' || result == 'incorrect') && 
          checkInAge.inHours < 24 &&  // Only notify for relatively recent check-ins (last 24h)
          checkInKey != lastNotifiedId &&
          checkInKey != lastAcknowledgedId) {
        
        print("Issue detected: $responderName had a $result check-in");
        
        // Update tracking of notifications
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
          body: '$responderName had a $result check-in at $mostRecentTimeStr',
        );
        
        print("Notification sent for $responderName's $result check-in");
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

Widget _buildCheckInList() {
  final observerUid = AuthService.currentUserId;

  return FutureBuilder<DocumentSnapshot>(
    future: FirebaseFirestore.instance
        .collection('users')
        .doc(observerUid)
        .get(),
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        print("DEBUG UI: Waiting for observer data...");
        return const Center(child: CircularProgressIndicator());
      }
      
      final userData = snapshot.data!.data() as Map<String, dynamic>?;
      final observingMap = userData?['observing'] as Map<String, dynamic>? ?? {};
      final responderUids = observingMap.keys.toList();
      
      print("DEBUG UI: Observer data loaded. Linked responders: $responderUids");
      
      if (responderUids.isEmpty) {
        return const Center(
          child: Text('No responders linked yet. Add a responder to monitor.'),
        );
      }
      
      // For simplicity, show the first responder's check-ins
      final responderUid = responderUids.first;
      final responderName = observingMap[responderUid];
      
      print("DEBUG UI: Showing check-ins for responder: $responderName ($responderUid)");
      
      // Use a direct StreamBuilder for the check-ins to ensure we get real-time updates
      // This is for UI display only - separate from our polling mechanism
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Monitoring: $responderName', 
               style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('responder_status')
                  .doc(responderUid)
                  .collection('check_ins')
                  .orderBy('timestamp', descending: true)
                  .limit(10)
                  .snapshots(),
              builder: (context, checkInSnapshot) {
                print("DEBUG UI: Check-in stream update received");
                
                if (!checkInSnapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                
                final docs = checkInSnapshot.data!.docs;
                
                if (docs.isEmpty) {
                  print("DEBUG UI: No check-ins found for responder");
                  return const Center(child: Text('No check-ins found.'));
                }
                
                print("DEBUG UI: Found ${docs.length} check-ins");
                
                final latest = docs.first;
                final latestId = latest.id;
                final latestData = latest.data() as Map<String, dynamic>;
                final latestResult = latestData['result'];
                final latestTimestamp = latestData['timestamp'];
                
                print("DEBUG UI: Latest check-in - ID: $latestId, Result: $latestResult, Timestamp: $latestTimestamp");
                
                // Use a combined key of responderUid:checkInId for acknowledgements
                final latestKey = "$responderUid:$latestId";
                final needsAck =
                  (latestResult == 'missed' || latestResult == 'incorrect') &&
                  latestKey != lastAcknowledgedId;
                
                if (needsAck) {
                  print("DEBUG UI: Check-in requires acknowledgment");
                }
                
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
                          return _buildCheckInTile(doc.id, doc.data() as Map<String, dynamic>);
                        },
                      ),
                    ),
                  ],
                );
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
    return Scaffold(
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
      // Use a Container with constraints instead of a SingleChildScrollView
      // This gives the content a fixed size context
      body: Container(
        constraints: BoxConstraints(
          // Use MediaQuery to get the screen size
          maxHeight: MediaQuery.of(context).size.height -
              AppBar().preferredSize.height -
              MediaQuery.of(context).padding.top,
        ),
        padding: const EdgeInsets.all(16.0),
        child: _buildCheckInList(),
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
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'danoggin_alerts',  // different channel ID
      'Danoggin Urgent Alerts',
      channelDescription: 'Used for critical alerts about missed or incorrect check-ins',
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
      'danoggin_direct_test',  // Channel ID
      'Danoggin Test Channel',  // Channel name
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
