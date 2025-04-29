// New model: UserQuestionPacks.dart
class UserQuestionPacks {
  final String userId;
  final List<String> subscribedPackIds;
  
  UserQuestionPacks({
    required this.userId,
    required this.subscribedPackIds,
  });
  
  factory UserQuestionPacks.fromJson(Map<String, dynamic> json) {
    return UserQuestionPacks(
      userId: json['userId'] as String,
      subscribedPackIds: List<String>.from(json['subscribedPackIds'] ?? []),
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'subscribedPackIds': subscribedPackIds,
    };
  }
}
