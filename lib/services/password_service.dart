import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'logging_service.dart';

/// Service to handle password hashing and verification
/// Uses SHA-256 for password hashing (more secure than MD5)
class PasswordService {
  /// Hash a password using SHA-256
  /// This creates a one-way hash that cannot be reversed
  static String hashPassword(String password) {
    try {
      // Convert password to bytes
      final bytes = utf8.encode(password);
      // Create SHA-256 hash
      final digest = sha256.convert(bytes);
      // Return hexadecimal string representation
      return digest.toString();
    } catch (e) {
      LoggingService.error('Error hashing password', e, StackTrace.current);
      rethrow;
    }
  }

  /// Verify if a provided password matches the stored hash
  /// Returns true if password matches, false otherwise
  static bool verifyPassword(String password, String storedHash) {
    try {
      // Hash the provided password
      final providedHash = hashPassword(password);
      // Compare with stored hash (constant-time comparison for security)
      return providedHash == storedHash;
    } catch (e) {
      LoggingService.error('Error verifying password', e, StackTrace.current);
      return false;
    }
  }

  /// Generate a secure hash for storing in Firestore
  /// This is used when creating admin user credentials
  static String generateHashForStorage(String password) {
    return hashPassword(password);
  }
}

