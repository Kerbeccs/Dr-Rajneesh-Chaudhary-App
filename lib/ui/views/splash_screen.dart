import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../services/maintenance_service.dart';
import 'maintenance_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // Check maintenance status first, then check auth state
    _checkMaintenanceAndAuth();
  }

  Future<void> _checkMaintenanceAndAuth() async {
    // Wait a bit for Firebase to initialize
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    // Check maintenance status first
    final maintenanceStatus = await MaintenanceService.checkMaintenanceStatus();

    if (maintenanceStatus['isMaintenance'] == true) {
      // App is under maintenance, show maintenance screen
      if (mounted) {
        final currentVersion = await _getAppVersion();
        final minVersion = maintenanceStatus['minVersion'] as String?;
        final needsUpdate = minVersion != null &&
            !MaintenanceService.isVersionCompatible(currentVersion, minVersion);

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => MaintenanceScreen(
              message: maintenanceStatus['message'] as String?,
              showUpdateButton: needsUpdate,
            ),
          ),
        );
      }
      return;
    }

    // Check version compatibility
    final currentVersion = await _getAppVersion();
    final minVersion = maintenanceStatus['minVersion'] as String?;
    if (minVersion != null &&
        !MaintenanceService.isVersionCompatible(currentVersion, minVersion)) {
      // App version is outdated, show maintenance screen with update button
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const MaintenanceScreen(
              message:
                  'Please update the app to the latest version to continue.',
              showUpdateButton: true,
            ),
          ),
        );
      }
      return;
    }

    // App is operational, check auth state
    if (!mounted) return;

    final authViewModel = Provider.of<AuthViewModel>(context, listen: false);

    // First, try to restore session from saved data (Keep me logged in)
    final sessionRestored = await authViewModel.restoreSessionFromStorage();

    // Check if user is already logged in (Firebase Auth or restored session)
    final user = authViewModel.user;
    final currentUser = authViewModel.currentUser;

    if ((user != null && currentUser != null) ||
        (sessionRestored && currentUser != null)) {
      // User is logged in (either Firebase Auth or restored session), redirect based on role
      final role = currentUser.role;
      if (mounted) {
        if (role == 'doctor') {
          Navigator.pushReplacementNamed(context, '/doctor');
        } else if (role == 'compounder') {
          Navigator.pushReplacementNamed(context, '/compounder');
        } else {
          Navigator.pushReplacementNamed(context, '/patient');
        }
      }
    } else {
      // User is not logged in, go to login screen
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    }
  }

  Future<String> _getAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      return packageInfo.version; // Returns "1.0.0" format
    } catch (e) {
      return '1.0.0'; // Default version if unable to get
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/logos/splash.png',
              width: 350,
              height: 350,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 20),
            const Text(
              'Dr. Rajnish Chaudhary',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
