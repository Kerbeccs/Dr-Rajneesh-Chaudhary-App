class FeedbackModel {
  final String id;
  final String patientId;
  final String patientName;
  final String comment;
  final int rating; // 1-5 rating (1=worst, 5=best)
  final DateTime createdAt;

  FeedbackModel({
    required this.id,
    required this.patientId,
    required this.patientName,
    required this.comment,
    required this.rating,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'patientId': patientId,
      'patientName': patientName,
      'comment': comment,
      'rating': rating,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory FeedbackModel.fromMap(Map<String, dynamic> map) {
    return FeedbackModel(
      id: map['id'] ?? '',
      patientId: map['patientId'] ?? '',
      patientName: map['patientName'] ?? '',
      comment: map['comment'] ?? '',
      rating: map['rating'] ?? 3,
      createdAt: DateTime.parse(map['createdAt']),
    );
  }
}
