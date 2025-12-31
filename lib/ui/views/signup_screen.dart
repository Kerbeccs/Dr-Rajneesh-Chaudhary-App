import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../viewmodels/auth_viewmodel.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/password_service.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController =
      TextEditingController();
  final TextEditingController nameController = TextEditingController();
  final TextEditingController ageController = TextEditingController();
  final TextEditingController otpController = TextEditingController();

  bool otpFieldVisible = false;

  String _formatPhoneNumber(String input) {
    String digits = input.replaceAll(RegExp(r'[^\d+]'), '');
    if (digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    if (!digits.startsWith('+')) {
      if (digits.length == 10) {
        digits = '+91$digits';
      } else {
        digits = '+$digits';
      }
    }
    return digits;
  }

  Future<void> _sendOtpForSignup() async {
    final authViewModel = Provider.of<AuthViewModel>(context, listen: false);

    if (nameController.text.isEmpty ||
        phoneController.text.isEmpty ||
        ageController.text.isEmpty ||
        passwordController.text.isEmpty ||
        confirmPasswordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill in all fields'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (passwordController.text != confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Passwords do not match'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    int? age = int.tryParse(ageController.text);
    if (age == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid age'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Check if phone number already exists
    final formattedPhone = _formatPhoneNumber(phoneController.text.trim());
    final firestore = FirebaseFirestore.instance;
    final query = await firestore
        .collection('users')
        .where('phoneNumber', isEqualTo: formattedPhone)
        .limit(1)
        .get();

    if (query.docs.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Phone number already registered. Please login instead.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Send OTP for signup (doesn't require existing user)
    try {
      // Send OTP and wait for result
      await authViewModel.sendOtpForSignup(phoneController.text.trim());

      // Wait for Firebase callback to complete (polling with timeout)
      // Give Firebase enough time to process the request before checking for errors
      bool otpSent = false;
      String? finalError;

      // Wait up to 5 seconds (50 * 100ms) for Firebase to respond
      for (int i = 0; i < 50; i++) {
        await Future.delayed(const Duration(milliseconds: 100));

        // If OTP was sent successfully, break immediately
        if (authViewModel.otpSent) {
          otpSent = true;
          finalError = null; // Clear any temporary errors
          break;
        }

        // Only check for errors after waiting at least 1 second (10 iterations)
        // This prevents showing temporary errors that Firebase clears when OTP is sent
        if (i >= 10 &&
            authViewModel.phoneAuthError != null &&
            !authViewModel.otpSent) {
          finalError = authViewModel.phoneAuthError;
          // Continue checking in case OTP gets sent after error is cleared
        }
      }

      // Final check: if OTP was sent, use that; otherwise use the error
      if (authViewModel.otpSent) {
        otpSent = true;
        finalError = null;
      } else if (finalError == null && authViewModel.phoneAuthError != null) {
        finalError = authViewModel.phoneAuthError;
      }

      // Check if OTP was sent successfully
      if (otpSent) {
        // OTP sent successfully, show OTP field
        setState(() {
          otpFieldVisible = true;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('OTP sent successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        // OTP failed to send, show error only if we're sure it failed
        if (mounted && finalError != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(finalError),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _verifyOtpAndSignup() async {
    final authViewModel = Provider.of<AuthViewModel>(context, listen: false);

    if (otpController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter OTP'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final otpVerified =
        await authViewModel.verifyOtpAndLogin(otpController.text.trim());

    // For signup, we only need Firebase Auth to succeed (user won't exist in Firestore yet)
    // Check if Firebase user exists (not Firestore currentUser)
    if (otpVerified && authViewModel.user != null) {
      // User is verified via OTP, now create user profile in Firestore
      final formattedPhone = _formatPhoneNumber(phoneController.text.trim());
      final firestore = FirebaseFirestore.instance;
      final user = authViewModel.user;

      if (user != null) {
        int? age = int.tryParse(ageController.text);
        // Hash password before storing for security
        final passwordHash =
            PasswordService.hashPassword(passwordController.text);
        await firestore.collection('users').doc(user.uid).set({
          'uid': user.uid,
          'phoneNumber': formattedPhone,
          'passwordHash': passwordHash, // Store hashed password for security
          'patientName': nameController.text.trim(),
          'age': age ?? 0,
          'role': 'patient',
          'createdAt': FieldValue.serverTimestamp(),
        });

        // Reload user data after creating in Firestore
        await authViewModel.loadUserData();

        if (mounted) {
          Navigator.pushReplacementNamed(context, '/patient');
        }
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(authViewModel.phoneAuthError ?? 'OTP verification failed'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authViewModel = Provider.of<AuthViewModel>(context);

    return Scaffold(
      appBar: AppBar(title: const Text("Sign Up")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Show form fields if OTP hasn't been sent yet
            if (!otpFieldVisible && !authViewModel.otpSent) ...[
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: "Full Name"),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: phoneController,
                decoration: const InputDecoration(labelText: "Phone Number"),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: ageController,
                decoration: const InputDecoration(labelText: "Age"),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: passwordController,
                decoration: const InputDecoration(labelText: "Password"),
                obscureText: true,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: confirmPasswordController,
                decoration:
                    const InputDecoration(labelText: "Confirm Password"),
                obscureText: true,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: authViewModel.isLoading ? null : _sendOtpForSignup,
                child: const Text("Send OTP"),
              ),
            ],
            // Show OTP input field if OTP was sent (check both local state and ViewModel)
            if (otpFieldVisible || authViewModel.otpSent) ...[
              const Text(
                'Enter the OTP sent to your phone',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: otpController,
                decoration: const InputDecoration(labelText: "Enter OTP"),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: authViewModel.isLoading ? null : _verifyOtpAndSignup,
                child: const Text("Verify & Sign Up"),
              ),
            ],
            const SizedBox(height: 20),
            if (authViewModel.isLoading)
              const Center(child: CircularProgressIndicator()),
            if (authViewModel.errorMessage != null)
              Text(
                authViewModel.errorMessage!,
                style: const TextStyle(color: Colors.red),
              ),
            if (authViewModel.phoneAuthError != null)
              Text(
                authViewModel.phoneAuthError!,
                style: const TextStyle(color: Colors.red),
              ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () =>
                  Navigator.pushReplacementNamed(context, '/login'),
              child: const Text("Already have an account? Login"),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    phoneController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    nameController.dispose();
    ageController.dispose();
    otpController.dispose();
    super.dispose();
  }
}
