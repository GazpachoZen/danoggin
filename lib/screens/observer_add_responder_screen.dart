
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:danoggin/services/auth_service.dart';

class ObserverAddResponderScreen extends StatefulWidget {
  const ObserverAddResponderScreen({super.key});

  @override
  State<ObserverAddResponderScreen> createState() => _ObserverAddResponderScreenState();
}

class _ObserverAddResponderScreenState extends State<ObserverAddResponderScreen> {
  final TextEditingController _codeController = TextEditingController();
  bool _loading = false;
  String? _message;

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

    final observerUid = AuthService.currentUserId;
    final observerSnapshot = await FirebaseFirestore.instance.collection('users').doc(observerUid).get();
    final observerName = observerSnapshot.data()?['name'] ?? 'Unnamed';

    // Update responder's document
    await FirebaseFirestore.instance
        .collection('users')
        .doc(responderUid)
        .set({
          'linkedObservers': {observerUid: observerName}
        }, SetOptions(merge: true));

    // Update observer's document
    await FirebaseFirestore.instance
        .collection('users')
        .doc(observerUid)
        .set({
          'observing': {responderUid: responderName}
        }, SetOptions(merge: true));

    setState(() {
      _loading = false;
      _message = 'You are now linked to $responderName!';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Link to a Responder')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter the 6-character invite code from your responder:', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 16),
            TextField(
              controller: _codeController,
              textCapitalization: TextCapitalization.characters,
              maxLength: 6,
              decoration: const InputDecoration(
                hintText: 'ABC123',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            if (_loading) const CircularProgressIndicator(),
            if (!_loading)
              ElevatedButton(
                onPressed: _linkToResponder,
                child: const Text('Link'),
              ),
            if (_message != null) ...[
              const SizedBox(height: 20),
              Text(_message!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
    );
  }
}
