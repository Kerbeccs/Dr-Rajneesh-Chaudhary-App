import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../services/database_service.dart';
import '../services/compounder_payment_service.dart';
import '../services/whatsapp_service.dart';
import '../utils/locator.dart'; // Import DI locator

class CompounderBookingViewModel extends ChangeNotifier {
  // Use dependency injection for shared service instances
  // All CompounderBookingViewModel instances share the same services
  // Benefits: consistent state, reduced memory, easier testing
  final DatabaseService _db;
  final FirebaseFirestore _firestore;
  final CompounderPaymentService _paymentService;

  bool _isProcessing = false;
  String? _errorMessage;

  bool get isProcessing => _isProcessing;
  String? get errorMessage => _errorMessage;

  // Constructor with optional parameters for testing
  // Uses DI container (locator) if not provided
  CompounderBookingViewModel({
    DatabaseService? databaseService,
    FirebaseFirestore? firestore,
    CompounderPaymentService? paymentService,
  })  : _db = databaseService ?? locator<DatabaseService>(),
        _firestore = firestore ?? locator<FirebaseFirestore>(),
        _paymentService = paymentService ?? locator<CompounderPaymentService>();

  Future<void> _createAppointmentDocument({
    required int seatNumber,
    required DateTime selectedDate,
    required String selectedTimeSlotKey, // 'morning' | 'afternoon' | 'evening'
    required String patientName,
    required String patientToken,
  }) async {
    final formattedDate = DateFormat('yyyy-MM-dd').format(selectedDate);
    final timeRange = _getTimeSlotRange(selectedTimeSlotKey);

    // Use transaction to prevent double-booking when multiple users click same seat
    await _firestore.runTransaction((transaction) async {
      // CRITICAL: Check if seat is already booked BEFORE creating appointment
      // This prevents double-booking when multiple users click the same seat simultaneously
      // Query for existing appointments with same date, time, and seat number
      final conflictQuery = _firestore
          .collection('appointments')
          .where('appointmentDate', isEqualTo: formattedDate)
          .where('appointmentTime', isEqualTo: timeRange)
          .where('seatNumber', isEqualTo: seatNumber)
          .where('status',
              whereIn: ['pending', 'in_progress', 'confirmed', 'completed']);

      // Get the query snapshot within transaction
      final conflictSnapshot = await conflictQuery.get();

      // If seat is already booked, throw error to abort transaction
      if (conflictSnapshot.docs.isNotEmpty) {
        throw Exception(
            'Seat $seatNumber is already booked for this time slot. Please select another seat.');
      }

      // Seat is available - create appointment atomically
      final appointmentRef = _firestore.collection('appointments').doc();
      transaction.set(appointmentRef, {
        'patientId': 'compounder_action',
        'patientToken': patientToken,
        'patientName': patientName,
        'seatNumber': seatNumber,
        'appointmentDate': formattedDate,
        'appointmentTime': timeRange,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  String _getTimeSlotRange(String timeSlot) {
    switch (timeSlot) {
      case 'morning':
        return '9:30 AM - 2:30 PM'; // Morning: 9:30-2:30
      case 'afternoon':
        return '3:00 PM - 5:00 PM'; // Afternoon: 3:00-5:00
      case 'evening':
        return '5:30 PM - 8:00 PM'; // Evening: 5:30-8:00
      default:
        return '';
    }
  }

  Future<String> _createNewPatient({
    required String name,
    required String mobile,
    required int ageYears,
    required int ageMonths,
    required int ageDays,
    String? address,
    String? userPhoneNumber,
    required DateTime appointmentDate,
  }) async {
    return _db.createPatientAfterPayment(
      name: name,
      mobileNumber: mobile,
      ageYears: ageYears,
      ageMonths: ageMonths,
      ageDays: ageDays,
      address: address,
      userPhoneNumber: userPhoneNumber,
      appointmentDate: appointmentDate,
    );
  }

  Future<void> _updateExistingPatientVisit(String tokenId,
      {required DateTime appointmentDate}) async {
    await _db.updatePatientLastVisited(tokenId,
        appointmentDate: appointmentDate);
  }

  // Direct booking without payment (when fee is valid within 5 days)
  Future<void> bookForExistingTokenWithoutPayment({
    required String tokenId,
    required String patientNameFallback,
    required String mobileFallback,
    required int seatNumber,
    required DateTime selectedDate,
    required String selectedTimeSlotKey,
  }) async {
    if (_isProcessing) return;
    _isProcessing = true;
    _errorMessage = null;
    notifyListeners();
    try {
      // Fetch patient details if available
      String name = patientNameFallback;
      String mobile = mobileFallback;
      final snap = await _firestore
          .collection('patients')
          .where('tokenId', isEqualTo: tokenId)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        final data = snap.docs.first.data();
        name = data['name'] ?? name;
        mobile = data['mobileNumber'] ?? mobile;
      }

      // Do NOT update lastVisited - fee is still valid
      await _createAppointmentDocument(
        seatNumber: seatNumber,
        selectedDate: selectedDate,
        selectedTimeSlotKey: selectedTimeSlotKey,
        patientName: name,
        patientToken: tokenId,
      );

      // Send WhatsApp notification to doctor
      final formattedDate = DateFormat('yyyy-MM-dd').format(selectedDate);
      final timeRange = _getTimeSlotRange(selectedTimeSlotKey);
      await WhatsAppService.sendBookingNotification(
        patientName: name,
        patientToken: tokenId,
        seatNumber: seatNumber,
        appointmentDate: formattedDate,
        appointmentTime: timeRange,
      );

      // No payment logging for free booking
    } catch (e) {
      _errorMessage = e.toString();
      rethrow;
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  Future<void> bookForExistingToken({
    required String tokenId,
    required String patientNameFallback,
    required String mobileFallback,
    required int seatNumber,
    required DateTime selectedDate,
    required String selectedTimeSlotKey,
    required String method, // 'cash' | 'online'
  }) async {
    if (_isProcessing) return;
    _isProcessing = true;
    _errorMessage = null;
    notifyListeners();
    try {
      // Fetch patient details if available
      String name = patientNameFallback;
      String mobile = mobileFallback;
      final snap = await _firestore
          .collection('patients')
          .where('tokenId', isEqualTo: tokenId)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        final data = snap.docs.first.data();
        name = data['name'] ?? name;
        mobile = data['mobileNumber'] ?? mobile;
      }

      // Update lastVisited when payment is made (with appointment date)
      await _updateExistingPatientVisit(tokenId, appointmentDate: selectedDate);
      await _createAppointmentDocument(
        seatNumber: seatNumber,
        selectedDate: selectedDate,
        selectedTimeSlotKey: selectedTimeSlotKey,
        patientName: name,
        patientToken: tokenId,
      );

      // Send WhatsApp notification to doctor
      final formattedDate = DateFormat('yyyy-MM-dd').format(selectedDate);
      final timeRange = _getTimeSlotRange(selectedTimeSlotKey);
      await WhatsAppService.sendBookingNotification(
        patientName: name,
        patientToken: tokenId,
        seatNumber: seatNumber,
        appointmentDate: formattedDate,
        appointmentTime: timeRange,
      );

      // Log payment
      await _paymentService.addPaymentRecord(
        patientToken: tokenId,
        patientName: name,
        mobileNumber: mobile,
        age: 0,
        method: method,
      );
    } catch (e) {
      _errorMessage = e.toString();
      rethrow;
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  Future<String> bookForNewPatient({
    required String name,
    required String mobile,
    required int ageYears,
    required int ageMonths,
    required int ageDays,
    String? address,
    required int seatNumber,
    required DateTime selectedDate,
    required String selectedTimeSlotKey,
    required String method,
    String? userPhoneNumber,
  }) async {
    if (_isProcessing) return '';
    _isProcessing = true;
    _errorMessage = null;
    notifyListeners();
    try {
      // No token limit for compounder - they can create unlimited tokens
      // (Removed 7 token limit check for compounder side)

      final tokenId = await _createNewPatient(
        name: name,
        mobile: mobile,
        ageYears: ageYears,
        ageMonths: ageMonths,
        ageDays: ageDays,
        address: address,
        userPhoneNumber: userPhoneNumber,
        appointmentDate: selectedDate,
      );

      await _createAppointmentDocument(
        seatNumber: seatNumber,
        selectedDate: selectedDate,
        selectedTimeSlotKey: selectedTimeSlotKey,
        patientName: name,
        patientToken: tokenId,
      );

      // Send WhatsApp notification to doctor
      final formattedDate = DateFormat('yyyy-MM-dd').format(selectedDate);
      final timeRange = _getTimeSlotRange(selectedTimeSlotKey);
      await WhatsAppService.sendBookingNotification(
        patientName: name,
        patientToken: tokenId,
        seatNumber: seatNumber,
        appointmentDate: formattedDate,
        appointmentTime: timeRange,
      );

      await _paymentService.addPaymentRecord(
        patientToken: tokenId,
        patientName: name,
        mobileNumber: mobile,
        age: 0, // Not used in payment record, keeping for compatibility
        method: method,
      );

      return tokenId;
    } catch (e) {
      _errorMessage = e.toString();
      rethrow;
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }
}
