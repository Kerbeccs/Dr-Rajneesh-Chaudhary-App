import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import '../services/logging_service.dart';
import '../services/token_cache_service.dart';
import '../services/auth_storage_service.dart';
import '../services/admin_auth_service.dart';

class AuthViewModel extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  User? _user;
  bool _isLoading = false;
  String? _errorMessage;
  UserModel? _currentUserModel;

  // --- PHONE/OTP AUTH FIELDS ---
  String? _verificationId;
  bool _otpSent = false;
  bool get otpSent => _otpSent;
  String? _phoneAuthError;
  String? get phoneAuthError => _phoneAuthError;

  User? get user => _user;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  UserModel? get currentUser => _currentUserModel;

  AuthViewModel() {
    _auth.authStateChanges().listen((User? user) {
      _user = user;
      if (user != null) {
        loadUserData();
      } else {
        _currentUserModel = null;
      }
      notifyListeners();
    });
  }

  Future<void> loadUserData() async {
    if (_user == null) return;

    try {
      final doc = await _firestore.collection('users').doc(_user!.uid).get();
      if (doc.exists && doc.data() != null) {
        _currentUserModel =
            UserModel.fromMap({...doc.data()!, 'uid': _user!.uid});
        notifyListeners();
      } else {
        // User data not found - silently handle without showing error
        _currentUserModel = null;
        LoggingService.warning('User data not found for UID: ${_user!.uid}');
      }
    } catch (e) {
      LoggingService.error('Error loading user data', e, StackTrace.current);
      _errorMessage = 'Error loading user data: $e';
      notifyListeners();
    }
  }

  Future<void> signIn(String email, String password) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (userCredential.user != null) {
        await loadUserData(); // Load user data after successful sign in
      }
    } on FirebaseAuthException catch (e) {
      _errorMessage = e.message ?? 'Authentication failed';
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    try {
      // Clear token ID cache when user logs out
      await TokenCacheService.clearAllCaches();
      // Clear saved session (keep me logged in)
      await AuthStorageService.clearSession();
      await _auth.signOut();
      _currentUserModel = null;
      notifyListeners();
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  Future<bool> loginAsDoctor(String email, String password) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      LoggingService.debug("Attempting to login as doctor with email: $email");

      UserCredential userCredential;
      try {
        // Try to sign in with email and password
        userCredential = await _auth.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
        LoggingService.info("Doctor login successful with existing account");
      } catch (e) {
        LoggingService.warning("Doctor login failed, creating new account: $e");
        // If sign in fails, create a new account
        userCredential = await _auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
        LoggingService.info("New doctor account created successfully");
      }

      // Check if user exists in Firestore
      final userDoc = await _firestore
          .collection('users')
          .doc(userCredential.user!.uid)
          .get();

      LoggingService.debug(
          "Checking if doctor exists in Firestore: ${userDoc.exists}");

      if (!userDoc.exists) {
        // Create doctor user model if first time sign in
        final userModel = UserModel(
          uid: userCredential.user!.uid,
          email: email,
          patientName: "Dr. Rajneesh Chaudhary",
          phoneNumber: "",
          age: 0,
          role: 'doctor',
        );

        // Save to Firestore
        await _firestore
            .collection('users')
            .doc(userCredential.user!.uid)
            .set(userModel.toMap());
        LoggingService.info("Created new doctor record in Firestore");
      } else {
        // Update userType to 'doctor' if not already set
        if (userDoc.data()?['role'] != 'doctor') {
          await _firestore
              .collection('users')
              .doc(userCredential.user!.uid)
              .update({'role': 'doctor'});
          LoggingService.info("Updated existing user to doctor type");
        } else {
          LoggingService.debug("User already has doctor type");
        }
      }

      return true;
    } catch (e) {
      LoggingService.error("Doctor login error", e, StackTrace.current);
      _errorMessage = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> updateUserProfile({
    required String patientName,
    required String phoneNumber,
    required int age,
    String? problemDescription,
  }) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      if (_user == null) {
        _errorMessage = 'No user logged in';
        return false;
      }

      await _firestore.collection('users').doc(_user!.uid).update({
        'patientName': patientName,
        'phoneNumber': phoneNumber,
        'age': age,
        if (problemDescription != null)
          'problemDescription': problemDescription,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await loadUserData();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Helper to format phone number to E.164 (default to +91 for 10-digit numbers)
  String formatPhoneNumber(String input) {
    String digits = input.replaceAll(RegExp(r'[^\d+]'), '');
    if (digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    if (!digits.startsWith('+')) {
      // Default to India (+91) if not present
      if (digits.length == 10) {
        digits = '+91$digits';
      } else {
        // Optionally, handle other lengths/countries or show error
        digits = '+$digits';
      }
    }
    return digits;
  }

  // --- SEND OTP FOR LOGIN ---
  // This method sends OTP only if the phone number is already registered in the database
  Future<void> sendOtpToPhone(String phoneNumber) async {
    _isLoading = true;
    _otpSent = false;
    _phoneAuthError = null;
    notifyListeners();
    try {
      // Format the phone number to E.164 format
      final formattedPhone = formatPhoneNumber(phoneNumber);

      // Check if the phone number is already registered in the database
      final query = await _firestore
          .collection('users')
          .where('phoneNumber', isEqualTo: formattedPhone)
          .limit(1)
          .get();

      // If no user found with this phone number, show error
      if (query.docs.isEmpty) {
        _phoneAuthError =
            'No user found with this phone number. Please sign up first.';
        _isLoading = false;
        notifyListeners();
        return;
      }

      // If user exists, proceed with sending OTP
      await _auth.verifyPhoneNumber(
        phoneNumber: formattedPhone,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential credential) async {
          // Auto-retrieval or instant verification
          await _auth.signInWithCredential(credential);
          await loadUserData();
          _otpSent = false;
          notifyListeners();
        },
        verificationFailed: (FirebaseAuthException e) {
          _phoneAuthError = e.message;
          _otpSent = false;
          _isLoading = false;
          notifyListeners();
        },
        codeSent: (String verificationId, int? resendToken) {
          _verificationId = verificationId;
          _otpSent = true;
          _phoneAuthError = null; // Clear any previous errors when OTP is sent successfully
          _isLoading = false;
          notifyListeners();
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
          _isLoading = false;
          notifyListeners();
        },
      );
    } catch (e) {
      _phoneAuthError = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- SEND OTP FOR SIGNUP ---
  // This method sends OTP for new user signup (doesn't check if user exists)
  Future<void> sendOtpForSignup(String phoneNumber) async {
    _isLoading = true;
    _otpSent = false;
    _phoneAuthError = null;
    notifyListeners();
    try {
      // Format the phone number to E.164 format
      final formattedPhone = formatPhoneNumber(phoneNumber);

      // Send OTP without checking if user exists (for signup)
      await _auth.verifyPhoneNumber(
        phoneNumber: formattedPhone,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential credential) async {
          // Auto-retrieval or instant verification
          // Keep _otpSent = true so UI shows OTP field for signup flow
          // The user still needs to complete the signup form
          await _auth.signInWithCredential(credential);
          _otpSent = true; // Changed from false to true
          notifyListeners();
        },
        verificationFailed: (FirebaseAuthException e) {
          _phoneAuthError = e.message;
          _otpSent = false;
          _isLoading = false;
          notifyListeners();
        },
        codeSent: (String verificationId, int? resendToken) {
          _verificationId = verificationId;
          _otpSent = true;
          _phoneAuthError = null; // Clear any previous errors when OTP is sent successfully
          _isLoading = false;
          notifyListeners();
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
          _isLoading = false;
          notifyListeners();
        },
      );
    } catch (e) {
      _phoneAuthError = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- VERIFY OTP ---
  Future<bool> verifyOtpAndLogin(String otp) async {
    if (_verificationId == null) {
      _phoneAuthError = 'No verification ID. Please request OTP again.';
      notifyListeners();
      return false;
    }
    _isLoading = true;
    _phoneAuthError = null;
    notifyListeners();
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: otp,
      );
      final userCredential = await _auth.signInWithCredential(credential);
      if (userCredential.user != null) {
        await loadUserData();

        // Always save session to keep user logged in until logout
        if (_currentUserModel != null) {
          await AuthStorageService.saveSession(
            phoneNumber: _currentUserModel!.phoneNumber,
            role: _currentUserModel!.role,
            uid: _currentUserModel!.uid,
            patientName: _currentUserModel!.patientName,
            age: _currentUserModel!.age,
          );
          LoggingService.debug('Session saved for OTP login');
        }

        _otpSent = false;
        _isLoading = false;
        notifyListeners();
        return true;
      }
      _isLoading = false;
      notifyListeners();
      return false;
    } on FirebaseAuthException catch (e) {
      _phoneAuthError = e.message;
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _phoneAuthError = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // --- LOGIN WITH PHONE + PASSWORD ---
  Future<bool> loginWithPhoneAndPassword(
      String phoneNumber, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // First, check if this is an admin user (doctor or compounder)
      // Admin credentials are stored in 'admin_credentials' collection with hashed passwords
      final adminUser = await AdminAuthService.authenticateAdmin(
        phoneNumber: phoneNumber,
        password: password,
      );

      if (adminUser != null) {
        // Admin authentication successful
        _currentUserModel = adminUser;

        // Always save session to keep user logged in until logout
        await AuthStorageService.saveSession(
          phoneNumber: _currentUserModel!.phoneNumber,
          role: _currentUserModel!.role,
          uid: _currentUserModel!.uid,
          patientName: _currentUserModel!.patientName,
          age: _currentUserModel!.age,
        );
        LoggingService.debug(
            'Session saved for admin login: ${adminUser.role}');

      _isLoading = false;
      notifyListeners();
      return true;
    }

      // If not admin, check regular users (patients)
      // Always query using E.164 format
      final formattedPhone = formatPhoneNumber(phoneNumber);
      final query = await _firestore
          .collection('users')
          .where('phoneNumber', isEqualTo: formattedPhone)
          .limit(1)
          .get();
      if (query.docs.isEmpty) {
        _errorMessage = 'No user found with this phone number.';
        _isLoading = false;
        notifyListeners();
        return false;
      }
      final userData = query.docs.first.data();

      // Check password (plaintext comparison for regular users - can be improved later)
      if (userData['password'] != password) {
        _errorMessage = 'Incorrect password.';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      _currentUserModel =
          UserModel.fromMap({...userData, 'uid': query.docs.first.id});

      // Always save session to keep user logged in until logout
      await AuthStorageService.saveSession(
        phoneNumber: _currentUserModel!.phoneNumber,
        role: _currentUserModel!.role,
        uid: _currentUserModel!.uid,
        patientName: _currentUserModel!.patientName,
        age: _currentUserModel!.age,
      );
      LoggingService.debug('Session saved for phone/password login');

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      LoggingService.error('Error during login', e, StackTrace.current);
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // --- RESTORE SESSION FROM SAVED DATA ---
  // This method is called on app start to restore user session if "Remember me" was checked
  Future<bool> restoreSessionFromStorage() async {
    try {
      final savedSession = await AuthStorageService.getSavedSession();
      if (savedSession == null) {
        LoggingService.debug('No saved session found');
        return false;
      }

      // Restore user model from saved session
      _currentUserModel = UserModel(
        uid: savedSession['uid'] ?? '',
        email: '',
        patientName: savedSession['patientName'] ?? '',
        phoneNumber: savedSession['phoneNumber'] ?? '',
        age: savedSession['age'] ?? 0,
        role: savedSession['role'] ?? 'patient',
        problemDescription: null,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        lastVisited: null,
      );

      LoggingService.debug(
          'Session restored for phone: ${savedSession['phoneNumber']}, role: ${savedSession['role']}');
      notifyListeners();
      return true;
    } catch (e) {
      LoggingService.error('Error restoring session', e, StackTrace.current);
      return false;
    }
  }

  // Get current user asynchronously
  Future<UserModel?> getCurrentUser() async {
    if (_currentUserModel != null) return _currentUserModel;
    await loadUserData();
    return _currentUserModel;
  }
}
