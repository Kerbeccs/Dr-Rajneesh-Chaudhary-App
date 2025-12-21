import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Screen shown when app is under maintenance
class MaintenanceScreen extends StatelessWidget {
  final String? message;
  final bool showUpdateButton;

  const MaintenanceScreen({
    super.key,
    this.message,
    this.showUpdateButton = false,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Maintenance Icon
                Icon(
                  Icons.build_circle_outlined,
                  size: 100,
                  color: Colors.orange.shade700,
                ),
                const SizedBox(height: 32),
                
                // Title
                Text(
                  'Under Maintenance',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade700,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                
                // Message
                Text(
                  message ??
                      'We are currently performing scheduled maintenance to improve your experience. Please check back later.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Colors.grey.shade700,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                
                // Update Button (if app version is outdated)
                if (showUpdateButton)
                  ElevatedButton.icon(
                    onPressed: () async {
                      // Open Play Store app page
                      final url = Uri.parse(
                        'https://play.google.com/store/apps/details?id=com.example.test_app',
                      );
                      if (await canLaunchUrl(url)) {
                        await launchUrl(url, mode: LaunchMode.externalApplication);
                      }
                    },
                    icon: const Icon(Icons.update),
                    label: const Text('Update App'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
                    ),
                  ),
                
                const SizedBox(height: 24),
                
                // Support Text
                Text(
                  'Thank you for your patience',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey.shade600,
                        fontStyle: FontStyle.italic,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

