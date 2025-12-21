import 'package:crypto/crypto.dart';
import 'dart:convert';

/// Utility class to generate password hashes for admin credentials setup
/// This is a helper tool - run this to get the hash for your password
class PasswordHashGenerator {
  /// Generate SHA-256 hash for a password
  /// Use this to get the hash value to store in Firestore
  static String generateHash(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Print hash for a password (for debugging/setup)
  static void printHash(String password) {
    final hash = generateHash(password);
    print('Password: $password');
    print('SHA-256 Hash: $hash');
    print('---');
  }

  /// Generate hashes for common admin passwords (for initial setup)
  static void generateCommonHashes() {
    print('=== Admin Password Hashes ===\n');
    printHash('drjc01');      // Doctor password
    printHash('assist00');    // Compounder password
  }
}

/// Run this as a standalone script to generate hashes
/// Usage: dart run lib/utils/password_hash_generator.dart
void main() {
  PasswordHashGenerator.generateCommonHashes();
  
  // You can also generate hash for custom password:
  // PasswordHashGenerator.printHash('your_password_here');
}

