import 'package:cloud_firestore/cloud_firestore.dart';

class PatientRecord {
  final String tokenId; // Unique, human-friendly token (e.g., PAT000123)
  final String name;
  final String mobileNumber;
  final int age;
  final String aadhaarLast4;
  // Optional patient attributes captured during first registration
  final String? sex; // 'male' | 'female' | 'other'
  final int? weightKg; // patient weight in kilograms
  final String? address; // patient address (max 50 characters)
  // Phone number of the logged-in user who booked
  final String? userPhoneNumber;
  final DateTime?
      lastVisited; // Interpreted as last successful fee payment date
  final DateTime createdAt;
  final DateTime? updatedAt;

  PatientRecord({
    required this.tokenId,
    required this.name,
    required this.mobileNumber,
    required this.age,
    required this.aadhaarLast4,
    this.sex,
    this.weightKg,
    this.address,
    this.userPhoneNumber,
    required this.createdAt,
    this.lastVisited,
    this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'tokenId': tokenId,
      'name': name,
      'mobileNumber': mobileNumber,
      'age': age,
      'aadhaarLast4': aadhaarLast4,
      // Only persist if provided
      if (sex != null) 'sex': sex,
      if (weightKg != null) 'weightKg': weightKg,
      if (address != null) 'address': address,
      if (userPhoneNumber != null) 'userPhoneNumber': userPhoneNumber,
      'lastVisited': lastVisited?.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  factory PatientRecord.fromMap(Map<String, dynamic> map) {
    return PatientRecord(
      tokenId: map['tokenId'] ?? '',
      name: map['name'] ?? '',
      mobileNumber: map['mobileNumber'] ?? '',
      age: (map['age'] is int)
          ? map['age'] as int
          : int.tryParse('${map['age']}') ?? 0,
      aadhaarLast4: map['aadhaarLast4'] ?? '',
      sex: map['sex'] as String?,
      weightKg: _parseInt(map['weightKg']),
      address: map['address'] as String?,
      userPhoneNumber: map['userPhoneNumber'] as String?,
      lastVisited: _parseDate(map['lastVisited']),
      createdAt: _parseDate(map['createdAt']) ?? DateTime.now(),
      updatedAt: _parseDate(map['updatedAt']),
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    try {
      return DateTime.parse(value.toString());
    } catch (_) {
      return null;
    }
  }

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    return int.tryParse(value.toString());
  }
}
