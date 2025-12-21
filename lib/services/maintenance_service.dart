import 'package:cloud_firestore/cloud_firestore.dart';
import 'logging_service.dart';

/// Service to check app maintenance status from Firestore
/// When maintenance is enabled, show maintenance screen to users
class MaintenanceService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _maintenanceDocPath = 'app_config/maintenance';

  /// Check if app is under maintenance
  /// Returns: {isMaintenance: bool, message: String?, minVersion: String?}
  static Future<Map<String, dynamic>> checkMaintenanceStatus() async {
    try {
      final doc = await _firestore.doc(_maintenanceDocPath).get();
      
      if (!doc.exists) {
        // No maintenance document exists, app is operational
        return {
          'isMaintenance': false,
          'message': null,
          'minVersion': null,
        };
      }

      final data = doc.data();
      if (data == null) {
        return {
          'isMaintenance': false,
          'message': null,
          'minVersion': null,
        };
      }

      final isMaintenance = data['enabled'] == true;
      final message = data['message'] as String? ?? 
          'The app is currently under maintenance. Please check back later.';
      final minVersion = data['minVersion'] as String?;

      return {
        'isMaintenance': isMaintenance,
        'message': message,
        'minVersion': minVersion,
      };
    } catch (e, st) {
      // If we can't check maintenance status, allow app to run
      // Log the error but don't block users
      LoggingService.error(
        'Error checking maintenance status',
        e,
        st,
      );
      return {
        'isMaintenance': false,
        'message': null,
        'minVersion': null,
      };
    }
  }

  /// Check if current app version meets minimum required version
  /// version format: "1.0.0" (from pubspec.yaml)
  /// minVersion format: "1.0.0" (from Firestore)
  static bool isVersionCompatible(String currentVersion, String? minVersion) {
    if (minVersion == null || minVersion.isEmpty) {
      return true; // No minimum version requirement
    }

    try {
      final current = _parseVersion(currentVersion);
      final minimum = _parseVersion(minVersion);

      // Compare major, minor, patch
      if (current[0] > minimum[0]) return true;
      if (current[0] < minimum[0]) return false;
      
      if (current[1] > minimum[1]) return true;
      if (current[1] < minimum[1]) return false;
      
      return current[2] >= minimum[2];
    } catch (e) {
      LoggingService.error('Error comparing versions', e);
      return true; // If version comparison fails, allow app to run
    }
  }

  /// Parse version string "1.0.0" to [major, minor, patch]
  static List<int> _parseVersion(String version) {
    final parts = version.split('.');
    return [
      int.tryParse(parts[0]) ?? 0,
      int.tryParse(parts[1]) ?? 0,
      int.tryParse(parts[2]) ?? 0,
    ];
  }
}

