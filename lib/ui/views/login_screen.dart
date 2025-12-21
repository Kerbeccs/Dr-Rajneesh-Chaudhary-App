import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../viewmodels/auth_viewmodel.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController otpController = TextEditingController();

  bool useOtp = false;
  bool otpFieldVisible = false;

  @override
  Widget build(BuildContext context) {
    final authViewModel = Provider.of<AuthViewModel>(context);

    return Scaffold(
      appBar: AppBar(title: const Text("Login")),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/logos/public-health.png',
                width: 200,
                height: 200,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 30),

              // Toggle login method
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ChoiceChip(
                    label: const Text('Login with Password'),
                    selected: !useOtp,
                    onSelected: (selected) {
                      setState(() {
                        useOtp = false;
                        otpFieldVisible = false;
                        otpController.clear();
                      });
                    },
                  ),
                  const SizedBox(width: 12),
                  ChoiceChip(
                    label: const Text('Login with OTP'),
                    selected: useOtp,
                    onSelected: (selected) {
                      setState(() {
                        useOtp = true;
                        otpFieldVisible = false;
                        otpController.clear();
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Phone number field (always shown)
              TextField(
                controller: phoneController,
                decoration: const InputDecoration(labelText: "Phone Number"),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 10),

              if (!useOtp) ...[
                // Password login
                TextField(
                  controller: passwordController,
                  decoration: const InputDecoration(labelText: "Password"),
                  obscureText: true,
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: authViewModel.isLoading
                      ? null
                      : () async {
                          String phone = phoneController.text.trim();
                          String password = passwordController.text.trim();
                          if (phone.isEmpty || password.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content:
                                    Text('Please enter phone and password'),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }
                          final success = await authViewModel
                              .loginWithPhoneAndPassword(phone, password);
                          if (success) {
                            if (mounted) {
                              final role = authViewModel.currentUser?.role;
                              if (role == 'doctor') {
                                Navigator.pushReplacementNamed(
                                    context, '/doctor');
                              } else if (role == 'compounder') {
                                Navigator.pushReplacementNamed(
                                    context, '/compounder');
                              } else {
                                Navigator.pushReplacementNamed(
                                    context, '/patient');
                              }
                            }
                          } else {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(authViewModel.errorMessage ??
                                      'Login failed'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        },
                  child: const Text("Login"),
                ),
              ] else ...[
                // OTP login
                if (!otpFieldVisible && !authViewModel.otpSent) ...[
                  ElevatedButton(
                    onPressed: authViewModel.isLoading
                        ? null
                        : () async {
                            String phone = phoneController.text.trim();
                            if (phone.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Please enter phone number'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                              return;
                            }
                            // Send OTP and wait for result
                            await authViewModel.sendOtpToPhone(phone);
                            
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
                              if (i >= 10 && authViewModel.phoneAuthError != null && !authViewModel.otpSent) {
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
                          },
                    child: const Text("Send OTP"),
                  ),
                ],
                if (authViewModel.otpSent || otpFieldVisible) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: otpController,
                    decoration: const InputDecoration(labelText: "Enter OTP"),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: authViewModel.isLoading
                        ? null
                        : () async {
                            String otp = otpController.text.trim();
                            if (otp.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Please enter OTP'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                              return;
                            }
                            final success =
                                await authViewModel.verifyOtpAndLogin(otp);
                            if (success) {
                              if (mounted) {
                                final role = authViewModel.currentUser?.role;
                                if (role == 'doctor') {
                                  Navigator.pushReplacementNamed(
                                      context, '/doctor');
                                } else if (role == 'compounder') {
                                  Navigator.pushReplacementNamed(
                                      context, '/compounder');
                                } else {
                                  Navigator.pushReplacementNamed(
                                      context, '/patient');
                                }
                              }
                            } else {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                        authViewModel.phoneAuthError ??
                                            'OTP verification failed'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            }
                          },
                    child: const Text("Verify & Login"),
                  ),
                ],
              ],

              const SizedBox(height: 20),
              if (authViewModel.isLoading) const CircularProgressIndicator(),
              if (authViewModel.errorMessage != null)
                Text(authViewModel.errorMessage!,
                    style: const TextStyle(color: Colors.red)),
              if (authViewModel.phoneAuthError != null)
                Text(authViewModel.phoneAuthError!,
                    style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 20),
              TextButton(
                onPressed: () => Navigator.pushNamed(context, '/signup'),
                child: const Text("Don't have an account? Sign Up"),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    phoneController.dispose();
    passwordController.dispose();
    otpController.dispose();
    super.dispose();
  }
}
