import 'package:cloud_firestore/cloud_firestore.dart';

class PatientRecord {
  final String tokenId; // Unique, human-friendly token (e.g., PAT000123)
  final String name;
  final String mobileNumber;
  final int ageYears;
  final int ageMonths;
  final int ageDays;
  // Optional patient attributes captured during first registration
  final String? sex; // 'male' | 'female' | 'other'
  final double? weightKg; // patient weight in kilograms (allows decimals)
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
    required this.ageYears,
    required this.ageMonths,
    required this.ageDays,
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
      'ageYears': ageYears,
      'ageMonths': ageMonths,
      'ageDays': ageDays,
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
    // Backward compatibility: if old 'age' field exists, convert to years/months/days
    int ageYears = 0;
    int ageMonths = 0;
    int ageDays = 0;
    
    if (map['ageYears'] != null && map['ageMonths'] != null && map['ageDays'] != null) {
      // New format
      ageYears = (map['ageYears'] is int) ? map['ageYears'] as int : int.tryParse('${map['ageYears']}') ?? 0;
      ageMonths = (map['ageMonths'] is int) ? map['ageMonths'] as int : int.tryParse('${map['ageMonths']}') ?? 0;
      ageDays = (map['ageDays'] is int) ? map['ageDays'] as int : int.tryParse('${map['ageDays']}') ?? 0;
    } else if (map['age'] != null) {
      // Old format: assume age is in years
      final oldAge = (map['age'] is int) ? map['age'] as int : int.tryParse('${map['age']}') ?? 0;
      ageYears = oldAge;
      ageMonths = 0;
      ageDays = 0;
    }
    
    return PatientRecord(
      tokenId: map['tokenId'] ?? '',
      name: map['name'] ?? '',
      mobileNumber: map['mobileNumber'] ?? '',
      ageYears: ageYears,
      ageMonths: ageMonths,
      ageDays: ageDays,
      sex: map['sex'] as String?,
      weightKg: _parseDouble(map['weightKg']),
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

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString());
  }
}
