import 'package:danoggin/utils/logger.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:danoggin/services/auth_service.dart';

class ResponderManageObserversScreen extends StatefulWidget {
  const ResponderManageObserversScreen({super.key});

  @override
  State<ResponderManageObserversScreen> createState() => _ResponderManageObserversScreenState();
}

class _ResponderManageObserversScreenState extends State<ResponderManageObserversScreen> {
  bool _loading = false;
  Map<String, String> _observers = {};
  bool _loadingObservers = true;
  bool _relationshipsChanged = false; // Track if any changes were made

  @override
  void initState() {
    super.initState();
    _loadCurrentObservers();
  }

  @override
  void dispose() {
    // When this screen is popped, return whether relationships changed
    if (_relationshipsChanged) {
      Navigator.of(context).pop(true);
    }
    super.dispose();
  }

  Future<void> _loadCurrentObservers() async {
    setState(() {
      _loadingObservers = true;
    });

    try {
      final responderUid = AuthService.currentUserId;
      final responderDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(responderUid)
          .get();
      
      final userData = responderDoc.data();
      if (userData != null && userData.containsKey('linkedObservers')) {
        final linkedObservers = userData['linkedObservers'] as Map<String, dynamic>;
        final observers = Map<String, String>.from(linkedObservers);
        
        setState(() {
          _observers = observers;
          _loadingObservers = false;
        });
      } else {
        setState(() {
          _observers = {};
          _loadingObservers = false;
        });
      }
    } catch (e) {
      Logger().e('Error loading observers: $e');
      setState(() {
        _loadingObservers = false;
      });
    }
  }

  Future<void> _removeObserver(String observerUid, String observerName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove $observerName?'),
        content: Text('$observerName will no longer be able to monitor your check-ins. They will need your invite code to reconnect later.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    ) ?? false;

    if (!confirmed) return;

    setState(() {
      _loading = true;
    });

    try {
      final responderUid = AuthService.currentUserId;
      
      // Get current responder data
      final responderDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(responderUid)
          .get();
      
      final linkedObserversData = Map<String, dynamic>.from(
          responderDoc.data()?['linkedObservers'] as Map<String, dynamic>);
      
      // Remove observer from responder's list
      linkedObserversData.remove(observerUid);
      
      // Update responder document
      await FirebaseFirestore.instance
          .collection('users')
          .doc(responderUid)
          .update({'linkedObservers': linkedObserversData});
      
      // Get observer's data
      final observerDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(observerUid)
          .get();
      
      if (observerDoc.exists) {
        final observingData = Map<String, dynamic>.from(
            observerDoc.data()?['observing'] as Map<String, dynamic>);
        
        // Remove responder from observer's list
        observingData.remove(responderUid);
        
        // Update observer document
        await FirebaseFirestore.instance
            .collection('users')
            .doc(observerUid)
            .update({'observing': observingData});
      }

      // Mark that relationships have changed
      _relationshipsChanged = true;

      // Reload the list
      await _loadCurrentObservers();
      
      // Show confirmation
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Removed $observerName')),
        );
      }
    } catch (e) {
      Logger().e('Error removing observer: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error removing observer. Please try again.')),
        );
      }
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      // Handle back button to ensure we return our result
      onWillPop: () async {
        Navigator.of(context).pop(_relationshipsChanged);
        return false; // We handled the pop ourselves
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Who is Observing You'),
          // Add a custom back button that returns our result
          leading: IconButton(
            icon: Icon(Icons.arrow_back),
            onPressed: () {
              Navigator.of(context).pop(_relationshipsChanged);
            },
          ),
        ),
        body: _loading ? 
          Center(child: CircularProgressIndicator()) :
          _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    if (_loadingObservers) {
      return Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_observers.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.person_search, size: 64, color: Colors.grey[400]),
              SizedBox(height: 16),
              Text(
                'No one is observing you yet',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'Share your invite code with trusted people\nwho need to monitor your check-ins.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'These people can monitor your check-ins:',
            style: TextStyle(fontSize: 16),
          ),
          SizedBox(height: 16),
          Text(
            '${_observers.length} ${_observers.length == 1 ? 'person' : 'people'} monitoring you',
            style: TextStyle(color: Colors.grey[600], fontStyle: FontStyle.italic),
          ),
          SizedBox(height: 8),
          Expanded(
            child: Card(
              margin: EdgeInsets.symmetric(vertical: 8.0),
              child: ListView.separated(
                itemCount: _observers.length,
                separatorBuilder: (context, index) => Divider(height: 1),
                itemBuilder: (context, index) {
                  final observerUid = _observers.keys.elementAt(index);
                  final observerName = _observers[observerUid]!;
                  
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.deepPurple[100],
                      child: Icon(Icons.person_outline, color: Colors.deepPurple[800]),
                    ),
                    title: Text(observerName),
                    subtitle: Text('Tap to remove'),
                    trailing: IconButton(
                      icon: Icon(Icons.remove_circle_outline, color: Colors.red),
                      onPressed: () => _removeObserver(observerUid, observerName),
                    ),
                    onTap: () => _removeObserver(observerUid, observerName),
                  );
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Text(
              'Removing an observer will prevent them from monitoring your check-ins. They will need your invite code to reconnect.',
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}