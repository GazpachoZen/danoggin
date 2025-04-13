
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:danoggin/services/auth_service.dart';
import 'package:flutter/services.dart';

class ResponderInviteCodeScreen extends StatefulWidget {
  const ResponderInviteCodeScreen({super.key});

  @override
  State<ResponderInviteCodeScreen> createState() => _ResponderInviteCodeScreenState();
}

class _ResponderInviteCodeScreenState extends State<ResponderInviteCodeScreen> {
  String? inviteCode;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadInviteCode();
  }

  Future<void> _loadInviteCode() async {
    final uid = AuthService.currentUserId;
    final snapshot = await FirebaseFirestore.instance.collection('users').doc(uid).get();

    setState(() {
      inviteCode = snapshot.data()?['inviteCode'] as String?;
      loading = false;
    });
  }

  void _copyToClipboard(BuildContext context) {
    if (inviteCode == null) return;
    Clipboard.setData(ClipboardData(text: inviteCode!));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Invite code copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Your Invite Code')),
      body: Center(
        child: loading
            ? const CircularProgressIndicator()
            : inviteCode == null
                ? const Text('No invite code found.')
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Share this code with your observer:', style: TextStyle(fontSize: 18)),
                      const SizedBox(height: 20),
                      SelectableText(
                        inviteCode!,
                        style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, letterSpacing: 4),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: () => _copyToClipboard(context),
                        icon: const Icon(Icons.copy),
                        label: const Text('Copy Code'),
                      ),
                    ],
                  ),
      ),
    );
  }
}
