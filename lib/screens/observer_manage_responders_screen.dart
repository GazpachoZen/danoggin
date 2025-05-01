import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:danoggin/services/auth_service.dart';

class ObserverManageRespondersScreen extends StatefulWidget {
  const ObserverManageRespondersScreen({super.key});

  @override
  State<ObserverManageRespondersScreen> createState() => _ObserverManageRespondersScreenState();
}

class _ObserverManageRespondersScreenState extends State<ObserverManageRespondersScreen> {
  final TextEditingController _codeController = TextEditingController();
  bool _loading = false;
  String? _message;
  Map<String, String> _responders = {};
  bool _loadingResponders = true;
  bool _relationshipsChanged = false; // Track if any changes were made

  @override
  void initState() {
    super.initState();
    _loadCurrentResponders();
  }

  @override
  void dispose() {
    // When this screen is popped, return whether relationships changed
    if (_relationshipsChanged) {
      Navigator.of(context).pop(true);
    }
    super.dispose();
  }

  Future<void> _loadCurrentResponders() async {
    setState(() {
      _loadingResponders = true;
    });

    try {
      final observerUid = AuthService.currentUserId;
      final observerDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(observerUid)
          .get();
      
      final userData = observerDoc.data();
      if (userData != null && userData.containsKey('observing')) {
        final observing = userData['observing'] as Map<String, dynamic>;
        final responders = Map<String, String>.from(observing);
        
        setState(() {
          _responders = responders;
          _loadingResponders = false;
        });
      } else {
        setState(() {
          _responders = {};
          _loadingResponders = false;
        });
      }
    } catch (e) {
      print('Error loading responders: $e');
      setState(() {
        _loadingResponders = false;
      });
    }
  }

  Future<void> _linkToResponder() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty || code.length != 6) {
      setState(() => _message = 'Enter a valid 6-character invite code.');
      return;
    }

    setState(() {
      _loading = true;
      _message = null;
    });

    try {
      final query = await FirebaseFirestore.instance
          .collection('users')
          .where('inviteCode', isEqualTo: code)
          .where('role', isEqualTo: 'responder')
          .get();

      if (query.docs.isEmpty) {
        setState(() {
          _loading = false;
          _message = 'No responder found with that code.';
        });
        return;
      }

      final responderDoc = query.docs.first;
      final responderUid = responderDoc.id;
      final responderName = responderDoc.data()['name'] ?? 'Unnamed';

      // Check if already linked
      if (_responders.containsKey(responderUid)) {
        setState(() {
          _loading = false;
          _message = 'You are already linked to $responderName.';
        });
        return;
      }

      final observerUid = AuthService.currentUserId;
      final observerSnapshot = await FirebaseFirestore.instance.collection('users').doc(observerUid).get();
      final observerName = observerSnapshot.data()?['name'] ?? 'Unnamed';

      // Update responder's document - merge with existing observers
      await FirebaseFirestore.instance
          .collection('users')
          .doc(responderUid)
          .set({
            'linkedObservers': {observerUid: observerName}
          }, SetOptions(merge: true));

      // Update observer's document - merge with existing responders
      await FirebaseFirestore.instance
          .collection('users')
          .doc(observerUid)
          .set({
            'observing': {responderUid: responderName}
          }, SetOptions(merge: true));

      // Mark that relationships have changed
      _relationshipsChanged = true;

      // Clear text field and reload responders
      _codeController.clear();
      await _loadCurrentResponders();

      setState(() {
        _loading = false;
        _message = 'You are now linked to $responderName!';
      });
    } catch (e) {
      print('Error linking to responder: $e');
      setState(() {
        _loading = false;
        _message = 'An error occurred. Please try again.';
      });
    }
  }

  Future<void> _unlinkFromResponder(String responderUid, String responderName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Unlink from $responderName?'),
        content: Text('You will no longer receive notifications about this responder. You can always link again later with their invite code.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Unlink'),
          ),
        ],
      ),
    ) ?? false;

    if (!confirmed) return;

    setState(() {
      _loading = true;
    });

    try {
      final observerUid = AuthService.currentUserId;
      
      // Get current observer data for merge
      final observerDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(observerUid)
          .get();
      
      final observingData = Map<String, dynamic>.from(
          observerDoc.data()?['observing'] as Map<String, dynamic>);
      
      // Remove responder from observer's list
      observingData.remove(responderUid);
      
      // Update observer document
      await FirebaseFirestore.instance
          .collection('users')
          .doc(observerUid)
          .update({'observing': observingData});
      
      // Get responder data
      final responderDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(responderUid)
          .get();
      
      if (responderDoc.exists) {
        final linkedObserversData = Map<String, dynamic>.from(
            responderDoc.data()?['linkedObservers'] as Map<String, dynamic>);
        
        // Remove observer from responder's list
        linkedObserversData.remove(observerUid);
        
        // Update responder document
        await FirebaseFirestore.instance
            .collection('users')
            .doc(responderUid)
            .update({'linkedObservers': linkedObserversData});
      }

      // Mark that relationships have changed
      _relationshipsChanged = true;

      // Reload the list
      await _loadCurrentResponders();
      
      // Show confirmation
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unlinked from $responderName')),
        );
      }
    } catch (e) {
      print('Error unlinking responder: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error unlinking. Please try again.')),
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
          title: const Text('Manage Responders'),
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
          SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Current responders section
                Text('Current Responders', 
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                SizedBox(height: 8),
                _buildCurrentRespondersList(),
                
                Divider(height: 32),
                
                // Add new responder section
                Text('Add New Responder', 
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                SizedBox(height: 8),
                const Text('Enter the 6-character invite code from your responder:', 
                  style: TextStyle(fontSize: 16)),
                SizedBox(height: 16),
                TextField(
                  controller: _codeController,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 6,
                  decoration: const InputDecoration(
                    hintText: 'ABC123',
                    border: OutlineInputBorder(),
                  ),
                ),
                SizedBox(height: 16),
                Center(
                  child: ElevatedButton.icon(
                    onPressed: _loading ? null : _linkToResponder,
                    icon: Icon(Icons.link),
                    label: const Text('Link to Responder'),
                  ),
                ),
                if (_message != null) ...[
                  SizedBox(height: 16),
                  Text(_message!, 
                    style: TextStyle(
                      color: _message!.contains('now linked') ? Colors.green : Colors.red,
                      fontWeight: FontWeight.bold
                    )
                  ),
                ],
              ],
            ),
          ),
      ),
    );
  }

  Widget _buildCurrentRespondersList() {
    if (_loadingResponders) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_responders.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24.0),
        child: Center(
          child: Text('No responders linked yet.',
            style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey[600])),
        ),
      );
    }

    return Card(
      margin: EdgeInsets.symmetric(vertical: 8.0),
      child: ListView.separated(
        shrinkWrap: true,
        physics: NeverScrollableScrollPhysics(),
        itemCount: _responders.length,
        separatorBuilder: (context, index) => Divider(height: 1),
        itemBuilder: (context, index) {
          final responderUid = _responders.keys.elementAt(index);
          final responderName = _responders[responderUid]!;
          
          return ListTile(
            title: Text(responderName),
            subtitle: Text('Tap to unlink'),
            trailing: IconButton(
              icon: Icon(Icons.link_off, color: Colors.red),
              onPressed: () => _unlinkFromResponder(responderUid, responderName),
            ),
            onTap: () => _unlinkFromResponder(responderUid, responderName),
          );
        },
      ),
    );
  }
}