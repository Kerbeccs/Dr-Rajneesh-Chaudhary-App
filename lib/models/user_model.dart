class UserModel {
  final String uid;
  final String email;
  final String patientName;
  final String phoneNumber;
  final int age;
  final String role;
  final String? problemDescription;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? lastVisited;

  UserModel({
    required this.uid,
    required this.email,
    required this.patientName,
    required this.phoneNumber,
    required this.age,
    required this.role,
    this.problemDescription,
    this.createdAt,
    this.updatedAt,
    this.lastVisited,
  });

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      uid: map['uid']?.toString() ?? '',
      email: map['email']?.toString() ?? '',
      patientName: map['patientName']?.toString() ?? '',
      phoneNumber: map['phoneNumber']?.toString() ?? '',
      age: (map['age'] as num?)?.toInt() ?? 0,
      role: map['role']?.toString() ?? 'patient',
      problemDescription: map['problemDescription']?.toString(),
      createdAt: map['createdAt']?.toDate() as DateTime?,
      updatedAt: map['updatedAt']?.toDate() as DateTime?,
      lastVisited: map['lastVisited']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      'patientName': patientName,
      'phoneNumber': phoneNumber,
      'age': age,
      'role': role,
      'problemDescription': problemDescription,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'lastVisited': lastVisited,
    };
  }
}
