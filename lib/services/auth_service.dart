
import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  // Ensure user is signed in anonymously
  static Future<User> ensureSignedIn() async {
    User? user = _auth.currentUser;
    if (user == null) {
      final result = await _auth.signInAnonymously();
      user = result.user;
    }
    return user!;
  }

  // Get current UID
  static String get currentUserId {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('User not signed in.');
    }
    return user.uid;
  }

  static User? get currentUser => _auth.currentUser;
}
