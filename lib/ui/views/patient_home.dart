import 'package:flutter/material.dart';

class PatientHomeScreen extends StatelessWidget {
  const PatientHomeScreen({super.key});
  // ✅ Ensure this extends StatelessWidget
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Patient Home')),
      body: const Center(child: Text('Patient Home Screen')),
    );
  }
}
