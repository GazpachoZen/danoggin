// In a new service file: question_pack_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:danoggin/services/auth_service.dart';
import 'package:danoggin/models/question_pack.dart';
import 'package:danoggin/models/user_question_packs.dart';

class QuestionPackService {
  static final _packSubscriptionsRef = 
      FirebaseFirestore.instance.collection('user_question_packs');
  static final _packsRef = 
      FirebaseFirestore.instance.collection('question_packs');
  
  // Get all available question packs
  static Future<List<QuestionPack>> getAvailablePacks() async {
    final snapshot = await _packsRef.get();
    return snapshot.docs.map((doc) => 
        QuestionPack.fromJson(doc.id, doc.data())).toList();
  }
  
  // Get user's subscribed packs
  static Future<UserQuestionPacks> getUserPacks() async {
    final uid = AuthService.currentUserId;
    final doc = await _packSubscriptionsRef.doc(uid).get();
    
    if (doc.exists) {
      final data = doc.data() as Map<String, dynamic>;
      return UserQuestionPacks.fromJson({
        'userId': uid,
        'subscribedPackIds': data['subscribedPackIds'] ?? [],
      });
    } else {
      // Default to demo_pack if no subscriptions exist
      return UserQuestionPacks(
        userId: uid,
        subscribedPackIds: ['demo_pack'],
      );
    }
  }
  
  // Update user's subscribed packs
  static Future<void> updateUserPacks(List<String> packIds) async {
    final uid = AuthService.currentUserId;
    await _packSubscriptionsRef.doc(uid).set({
      'subscribedPackIds': packIds,
    });
  }
  
  // Load all question packs that a user is subscribed to
  static Future<List<QuestionPack>> loadSubscribedPacks() async {
    final userPacks = await getUserPacks();
    final subscribedPacks = <QuestionPack>[];
    
    for (final packId in userPacks.subscribedPackIds) {
      try {
        final pack = await QuestionPack.loadFromFirestore(packId);
        subscribedPacks.add(pack);
      } catch (e) {
        print('Error loading pack $packId: $e');
      }
    }
    
    // Ensure we have at least the demo pack if nothing else is loaded
    if (subscribedPacks.isEmpty) {
      try {
        final demoPack = await QuestionPack.loadFromFirestore('demo_pack');
        subscribedPacks.add(demoPack);
      } catch (e) {
        print('Error loading fallback demo_pack: $e');
      }
    }
    
    return subscribedPacks;
  }
}