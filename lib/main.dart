import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'ui/views/splash_screen.dart';
import 'ui/views/login_screen.dart';
import 'ui/views/signup_screen.dart';
import 'ui/views/patient_dashboard.dart';
import 'ui/views/doctor_dashboard.dart';
import 'ui/views/compounder_dashboard.dart';
import 'ui/views/compounder_booking_screen.dart';
import 'ui/views/compounder_patients_list_screen.dart';
import 'viewmodels/auth_viewmodel.dart';
import 'viewmodels/booking_view_model.dart';
import 'viewmodels/doctor_appointments_view_model.dart';
import 'viewmodels/compounder_booking_view_model.dart';
import 'viewmodels/patient_appointment_status_view_model.dart';
import 'utils/locator.dart'; // Import DI setup

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Initialize Dependency Injection
  // This sets up all service singletons that will be shared across the app
  // Prevents multiple instances and ensures consistent state
  setupLocator();

  // Initialize Firebase App Check (required for Play Store builds)
  // This enables Play Integrity API for production and Debug provider for development
  try {
    await FirebaseAppCheck.instance.activate(
      androidProvider: kDebugMode
          ? AndroidProvider.debug // Use debug provider for local testing
          : AndroidProvider
              .playIntegrity, // Use Play Integrity for Play Store builds
    );
  } catch (e) {
    // If App Check fails (e.g., debug token not set, Play Integrity not available),
    // continue without App Check - Firebase Auth will still work but with reduced security
    // This is acceptable for local testing
    if (kDebugMode) {
      print('Firebase App Check initialization failed: $e');
      print('Continuing without App Check (acceptable for local testing)');
    }
  }

  // Initialize Crashlytics
  FlutterError.onError = (errorDetails) {
    // Pass Flutter errors to Crashlytics
    FirebaseCrashlytics.instance.recordFlutterFatalError(errorDetails);
  };

  // Pass non-Flutter errors to Crashlytics
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  // Enable Crashlytics collection (only in release mode)
  await FirebaseCrashlytics.instance
      .setCrashlyticsCollectionEnabled(!kDebugMode);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthViewModel()),
        ChangeNotifierProvider(create: (_) => BookingViewModel()),
        ChangeNotifierProvider(create: (_) => DoctorAppointmentsViewModel()),
        // ChangeNotifierProvider(create: (_) => ReportViewModel()),
        ChangeNotifierProvider(
            create: (_) => PatientAppointmentStatusViewModel()),
      ],
      child: MaterialApp(
        title: 'Dr. Rajnish',
        theme: ThemeData(
          primarySwatch: Colors.blue,
          useMaterial3: true,
          brightness: Brightness.light,
        ),
        darkTheme: ThemeData(
          primarySwatch: Colors.blue,
          useMaterial3: true,
          brightness: Brightness.dark,
        ),
        themeMode: ThemeMode.system,
        initialRoute: '/',
        routes: {
          '/': (context) => const SplashScreen(),
          '/login': (context) => const LoginScreen(),
          '/signup': (context) => const SignupScreen(),
          '/patient': (context) => const PatientDashboard(),
          '/doctor': (context) => const DoctorDashboard(),
          '/compounder': (context) => const CompounderDashboard(),
          '/compounder_booking': (context) => MultiProvider(
                providers: [
                  ChangeNotifierProvider(create: (_) => BookingViewModel()),
                  ChangeNotifierProvider(
                      create: (_) => CompounderBookingViewModel()),
                ],
                child: const CompounderBookingScreen(),
              ),
          '/compounder_patients': (context) =>
              const CompounderPatientsListScreen(),
        },
        onUnknownRoute: (settings) {
          return MaterialPageRoute(
            builder: (context) => const LoginScreen(),
          );
        },
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
