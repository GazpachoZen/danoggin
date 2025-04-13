
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:danoggin/models/user_role.dart';

class UserRepository {
  static final _usersRef = FirebaseFirestore.instance.collection('users');

  static Future<void> createUserProfile({
    required String uid,
    required String name,
    required UserRole role,
    String? inviteCode,
  }) async {
    final doc = _usersRef.doc(uid);
    final snapshot = await doc.get();

    if (!snapshot.exists) {
      await doc.set({
        'name': name,
        'role': role.name,
        'createdAt': FieldValue.serverTimestamp(),
        if (inviteCode != null) 'inviteCode': inviteCode,
      });
    } else {
      await doc.update({
        'name': name,
        'role': role.name,
        if (inviteCode != null) 'inviteCode': inviteCode,
      });
    }
  }

  static Future<UserRole?> getUserRole(String uid) async {
    final snapshot = await _usersRef.doc(uid).get();
    if (!snapshot.exists) return null;

    final data = snapshot.data();
    final roleStr = data?['role'] as String?;
    return UserRoleExtension.fromString(roleStr);
  }

  static Future<void> updateUserRole(String uid, UserRole role) async {
    await _usersRef.doc(uid).update({'role': role.name});
  }
}
