import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import 'password_service.dart';
import 'logging_service.dart';

/// Service to handle authentication for admin users (doctor and compounder)
/// Credentials are stored in Firestore 'admin_credentials' collection with hashed passwords
class AdminAuthService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Firestore collection name for admin credentials
  static const String _adminCollection = 'admin_credentials';

  /// Authenticate admin user (doctor or compounder) using phone and password
  /// Checks Firestore 'admin_credentials' collection for matching credentials
  /// Returns UserModel if authentication successful, null otherwise
  static Future<UserModel?> authenticateAdmin({
    required String phoneNumber,
    required String password,
  }) async {
    try {
      // Format phone number to E.164 format
      final formattedPhone = _formatPhoneNumber(phoneNumber);

      LoggingService.debug(
          'Attempting admin authentication for phone: $formattedPhone');

      // Query Firestore for admin credentials
      final query = await _firestore
          .collection(_adminCollection)
          .where('phoneNumber', isEqualTo: formattedPhone)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        LoggingService.warning(
            'No admin credentials found for phone: $formattedPhone');
        return null;
      }

      final adminData = query.docs.first.data();
      final storedPasswordHash = adminData['passwordHash'] as String?;
      final role = adminData['role'] as String?;
      final name = adminData['name'] as String?;
      final email = adminData['email'] as String? ?? '';
      final age = adminData['age'] as int? ?? 0;

      if (storedPasswordHash == null) {
        LoggingService.error('Password hash missing for admin: $formattedPhone',
            null, StackTrace.current);
        return null;
      }

      if (role == null || (role != 'doctor' && role != 'compounder')) {
        LoggingService.warning('Invalid role for admin: $role');
        return null;
      }

      // Verify password using hash comparison
      final isPasswordValid =
          PasswordService.verifyPassword(password, storedPasswordHash);

      if (!isPasswordValid) {
        LoggingService.warning('Invalid password for admin: $formattedPhone');
        return null;
      }

      // Create UserModel for authenticated admin
      final userModel = UserModel(
        uid: query.docs.first.id, // Use document ID as UID
        email: email,
        patientName: name ?? (role == 'doctor' ? 'Dr. Rajnish' : 'Compounder'),
        phoneNumber: formattedPhone,
        age: age,
        role: role,
        problemDescription: null,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        lastVisited: null,
      );

      LoggingService.info(
          'Admin authentication successful for: $formattedPhone, role: $role');
      return userModel;
    } catch (e) {
      LoggingService.error('Error authenticating admin', e, StackTrace.current);
      return null;
    }
  }

  /// Format phone number to E.164 format (e.g., +911234567890)
  static String _formatPhoneNumber(String input) {
    String digits = input.replaceAll(RegExp(r'[^\d+]'), '');
    if (digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    if (!digits.startsWith('+')) {
      // Default to India (+91) if not present
      if (digits.length == 10) {
        digits = '+91$digits';
      } else {
        digits = '+$digits';
      }
    }
    return digits;
  }

  /// Create admin credentials in Firestore (for initial setup)
  /// This should be called manually to set up admin users
  /// Returns true if successful, false otherwise
  static Future<bool> createAdminCredentials({
    required String phoneNumber,
    required String password,
    required String role, // 'doctor' or 'compounder'
    required String name,
    String? email,
    int? age,
  }) async {
    try {
      if (role != 'doctor' && role != 'compounder') {
        LoggingService.error(
            'Invalid role for admin: $role', null, StackTrace.current);
        return false;
      }

      final formattedPhone = _formatPhoneNumber(phoneNumber);

      // Hash the password before storing
      final passwordHash = PasswordService.hashPassword(password);

      // Check if admin already exists
      final existingQuery = await _firestore
          .collection(_adminCollection)
          .where('phoneNumber', isEqualTo: formattedPhone)
          .limit(1)
          .get();

      if (existingQuery.docs.isNotEmpty) {
        LoggingService.warning(
            'Admin credentials already exist for phone: $formattedPhone');
        // Update existing credentials
        await existingQuery.docs.first.reference.update({
          'passwordHash': passwordHash,
          'role': role,
          'name': name,
          if (email != null) 'email': email,
          if (age != null) 'age': age,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        LoggingService.info('Updated admin credentials for: $formattedPhone');
        return true;
      }

      // Create new admin credentials
      await _firestore.collection(_adminCollection).add({
        'phoneNumber': formattedPhone,
        'passwordHash': passwordHash, // Store hashed password, not plaintext
        'role': role,
        'name': name,
        'email': email ?? '',
        'age': age ?? 0,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      LoggingService.info(
          'Created admin credentials for: $formattedPhone, role: $role');
      return true;
    } catch (e) {
      LoggingService.error(
          'Error creating admin credentials', e, StackTrace.current);
      return false;
    }
  }
}
