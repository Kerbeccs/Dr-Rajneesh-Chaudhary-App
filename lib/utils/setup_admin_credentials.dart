import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../services/admin_auth_service.dart';
import '../services/password_service.dart';

/// Setup script to create admin credentials in Firestore
/// Run this once to migrate from hardcoded credentials to Firestore
/// 
/// Usage: Call setupAdminCredentials() from your app or create a temporary screen
Future<void> setupAdminCredentials() async {
  try {
    print('=== Setting up Admin Credentials ===\n');
    
    // Check if Firebase is initialized
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
    
    // Create doctor credentials
    print('Creating doctor credentials...');
    final doctorCreated = await AdminAuthService.createAdminCredentials(
      phoneNumber: '9415148932',
      password: 'drjc01',  // This will be hashed automatically
      role: 'doctor',
      name: 'Dr. Rajnish',
      email: 'drjc@example.com',
      age: 40,
    );
    
    if (doctorCreated) {
      print('✓ Doctor credentials created successfully');
      print('  Phone: +919415148932');
      print('  Password Hash: ${PasswordService.hashPassword('drjc01')}');
    } else {
      print('✗ Failed to create doctor credentials');
    }
    
    print('\n');
    
    // Create compounder credentials
    print('Creating compounder credentials...');
    final compounderCreated = await AdminAuthService.createAdminCredentials(
      phoneNumber: '1234567890',
      password: 'assist00',  // This will be hashed automatically
      role: 'compounder',
      name: 'Compounder',
      email: 'compounder@example.com',
      age: 0,
    );
    
    if (compounderCreated) {
      print('✓ Compounder credentials created successfully');
      print('  Phone: +911234567890');
      print('  Password Hash: ${PasswordService.hashPassword('assist00')}');
    } else {
      print('✗ Failed to create compounder credentials');
    }
    
    print('\n=== Setup Complete ===');
    print('\nYou can now login with:');
    print('Doctor: Phone 9415148932, Password drjc01');
    print('Compounder: Phone 1234567890, Password assist00');
    
  } catch (e) {
    print('Error setting up admin credentials: $e');
    rethrow;
  }
}

/// Check existing doctor/compounder data in users collection
Future<void> checkExistingAdminUsers() async {
  try {
    print('=== Checking Existing Admin Users ===\n');
    
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
    
    final firestore = FirebaseFirestore.instance;
    
    // Check for doctor in users collection
    final doctorQuery = await firestore
        .collection('users')
        .where('role', isEqualTo: 'doctor')
        .get();
    
    print('Doctors found in users collection: ${doctorQuery.docs.length}');
    for (var doc in doctorQuery.docs) {
      final data = doc.data();
      print('  - ${data['patientName'] ?? 'Unknown'} (${data['phoneNumber'] ?? 'No phone'})');
      print('    UID: ${doc.id}');
    }
    
    // Check for compounder in users collection
    final compounderQuery = await firestore
        .collection('users')
        .where('role', isEqualTo: 'compounder')
        .get();
    
    print('\nCompounders found in users collection: ${compounderQuery.docs.length}');
    for (var doc in compounderQuery.docs) {
      final data = doc.data();
      print('  - ${data['patientName'] ?? 'Unknown'} (${data['phoneNumber'] ?? 'No phone'})');
      print('    UID: ${doc.id}');
    }
    
    // Check admin_credentials collection
    final adminCredsQuery = await firestore
        .collection('admin_credentials')
        .get();
    
    print('\nAdmin credentials found: ${adminCredsQuery.docs.length}');
    for (var doc in adminCredsQuery.docs) {
      final data = doc.data();
      print('  - ${data['name'] ?? 'Unknown'} (${data['role'] ?? 'Unknown role'})');
      print('    Phone: ${data['phoneNumber'] ?? 'No phone'}');
    }
    
  } catch (e) {
    print('Error checking existing users: $e');
  }
}

