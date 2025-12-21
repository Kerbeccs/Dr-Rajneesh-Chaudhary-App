import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'logging_service.dart';

/// Service to handle "Keep me logged in" functionality
/// Stores user session data locally to enable automatic login on app restart
class AuthStorageService {
  // Keys for SharedPreferences
  static const String _rememberMeKey = 'remember_me';
  static const String _savedSessionKey = 'saved_user_session';
  static const String _sessionExpiryKey = 'session_expiry';
  
  // Default session expiry: 30 days
  static const int _defaultSessionExpiryDays = 30;

  /// Save "Remember me" preference
  static Future<void> setRememberMe(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_rememberMeKey, value);
      LoggingService.debug('Remember me preference saved: $value');
    } catch (e) {
      LoggingService.error('Error saving remember me preference', e, StackTrace.current);
    }
  }

  /// Get "Remember me" preference
  static Future<bool> getRememberMe() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_rememberMeKey) ?? false;
    } catch (e) {
      LoggingService.error('Error getting remember me preference', e, StackTrace.current);
      return false;
    }
  }

  /// Save user session data (phone number, role, etc.)
  /// This is called when user logs in with "Remember me" checked
  static Future<void> saveSession({
    required String phoneNumber,
    required String role,
    String? uid,
    String? patientName,
    int? age,
    int expiryDays = _defaultSessionExpiryDays,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Create session data map
      final sessionData = {
        'phoneNumber': phoneNumber,
        'role': role,
        if (uid != null) 'uid': uid,
        if (patientName != null) 'patientName': patientName,
        if (age != null) 'age': age,
      };
      
      // Save session data as JSON
      await prefs.setString(_savedSessionKey, jsonEncode(sessionData));
      
      // Save expiry timestamp (current time + expiry days)
      final expiryDate = DateTime.now().add(Duration(days: expiryDays));
      await prefs.setString(_sessionExpiryKey, expiryDate.toIso8601String());
      
      LoggingService.debug('User session saved for phone: $phoneNumber, role: $role');
    } catch (e) {
      LoggingService.error('Error saving user session', e, StackTrace.current);
    }
  }

  /// Get saved user session data if it exists and is not expired
  static Future<Map<String, dynamic>?> getSavedSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Check if session exists
      final sessionJson = prefs.getString(_savedSessionKey);
      if (sessionJson == null) {
        LoggingService.debug('No saved session found');
        return null;
      }
      
      // Check if session is expired
      final expiryStr = prefs.getString(_sessionExpiryKey);
      if (expiryStr != null) {
        final expiryDate = DateTime.parse(expiryStr);
        if (DateTime.now().isAfter(expiryDate)) {
          LoggingService.debug('Saved session has expired');
          await clearSession(); // Clear expired session
          return null;
        }
      }
      
      // Parse and return session data
      final sessionData = jsonDecode(sessionJson) as Map<String, dynamic>;
      LoggingService.debug('Retrieved saved session for phone: ${sessionData['phoneNumber']}');
      return sessionData;
    } catch (e) {
      LoggingService.error('Error getting saved session', e, StackTrace.current);
      return null;
    }
  }

  /// Check if a valid saved session exists
  static Future<bool> hasValidSession() async {
    final session = await getSavedSession();
    return session != null;
  }

  /// Clear saved session (called on logout)
  static Future<void> clearSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_savedSessionKey);
      await prefs.remove(_sessionExpiryKey);
      await prefs.remove(_rememberMeKey);
      LoggingService.debug('User session cleared');
    } catch (e) {
      LoggingService.error('Error clearing session', e, StackTrace.current);
    }
  }

  /// Get session expiry date
  static Future<DateTime?> getSessionExpiry() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final expiryStr = prefs.getString(_sessionExpiryKey);
      if (expiryStr != null) {
        return DateTime.parse(expiryStr);
      }
      return null;
    } catch (e) {
      LoggingService.error('Error getting session expiry', e, StackTrace.current);
      return null;
    }
  }
}

