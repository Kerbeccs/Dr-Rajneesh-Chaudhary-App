import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/patient_record.dart';
import 'logging_service.dart';

/// Service to cache patient token IDs locally on the device
/// This reduces Firestore reads and improves app performance
class TokenCacheService {
  static const String _cacheKeyPrefix = 'patient_tokens_';
  static const String _cacheTimestampKeyPrefix = 'patient_tokens_timestamp_';
  static const int _cacheExpiryHours = 24; // Cache valid for 24 hours

  /// Get cache key for a specific phone number
  static String _getCacheKey(String phoneNumber) {
    return '$_cacheKeyPrefix${phoneNumber.replaceAll(RegExp(r'[^0-9]'), '')}';
  }

  /// Get timestamp key for a specific phone number
  static String _getTimestampKey(String phoneNumber) {
    return '$_cacheTimestampKeyPrefix${phoneNumber.replaceAll(RegExp(r'[^0-9]'), '')}';
  }

  /// Check if cached data is still valid (not expired)
  static Future<bool> isCacheValid(String phoneNumber) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestampKey = _getTimestampKey(phoneNumber);
      final timestampStr = prefs.getString(timestampKey);

      if (timestampStr == null) return false;

      final timestamp = DateTime.parse(timestampStr);
      final now = DateTime.now();
      final difference = now.difference(timestamp).inHours;

      return difference < _cacheExpiryHours;
    } catch (e) {
      LoggingService.error('Error checking cache validity', e, StackTrace.current);
      return false;
    }
  }

  /// Save patient records to local cache
  static Future<void> cacheTokenIds(
      String phoneNumber, List<PatientRecord> records) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = _getCacheKey(phoneNumber);
      final timestampKey = _getTimestampKey(phoneNumber);

      // Convert records to JSON
      final recordsJson = records.map((r) => r.toMap()).toList();
      final jsonString = jsonEncode(recordsJson);

      // Save to cache
      await prefs.setString(cacheKey, jsonString);
      await prefs.setString(timestampKey, DateTime.now().toIso8601String());

      LoggingService.debug(
          'Cached ${records.length} token IDs for phone: $phoneNumber');
    } catch (e) {
      LoggingService.error('Error caching token IDs', e, StackTrace.current);
    }
  }

  /// Get cached patient records
  static Future<List<PatientRecord>?> getCachedTokenIds(
      String phoneNumber) async {
    try {
      // Check if cache is valid
      if (!await isCacheValid(phoneNumber)) {
        LoggingService.debug('Cache expired or not found for: $phoneNumber');
        return null;
      }

      final prefs = await SharedPreferences.getInstance();
      final cacheKey = _getCacheKey(phoneNumber);
      final jsonString = prefs.getString(cacheKey);

      if (jsonString == null) return null;

      // Parse JSON back to records
      final List<dynamic> recordsJson = jsonDecode(jsonString);
      final records = recordsJson
          .map((json) => PatientRecord.fromMap(
              Map<String, dynamic>.from(json)))
          .toList();

      LoggingService.debug(
          'Retrieved ${records.length} token IDs from cache for: $phoneNumber');
      return records;
    } catch (e) {
      LoggingService.error('Error retrieving cached token IDs', e,
          StackTrace.current);
      return null;
    }
  }

  /// Clear cache for a specific phone number
  static Future<void> clearCache(String phoneNumber) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = _getCacheKey(phoneNumber);
      final timestampKey = _getTimestampKey(phoneNumber);

      await prefs.remove(cacheKey);
      await prefs.remove(timestampKey);

      LoggingService.debug('Cleared cache for phone: $phoneNumber');
    } catch (e) {
      LoggingService.error('Error clearing cache', e, StackTrace.current);
    }
  }

  /// Clear all token ID caches (useful for logout)
  static Future<void> clearAllCaches() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();

      // Remove all cache keys
      for (final key in keys) {
        if (key.startsWith(_cacheKeyPrefix) ||
            key.startsWith(_cacheTimestampKeyPrefix)) {
          await prefs.remove(key);
        }
      }

      LoggingService.debug('Cleared all token ID caches');
    } catch (e) {
      LoggingService.error('Error clearing all caches', e, StackTrace.current);
    }
  }
}

