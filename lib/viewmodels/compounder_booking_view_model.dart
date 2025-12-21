import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../services/database_service.dart';
import '../services/compounder_payment_service.dart';
import '../services/whatsapp_service.dart';

class CompounderBookingViewModel extends ChangeNotifier {
  final DatabaseService _db;
  final FirebaseFirestore _firestore;
  final CompounderPaymentService _paymentService;

  bool _isProcessing = false;
  String? _errorMessage;

  bool get isProcessing => _isProcessing;
  String? get errorMessage => _errorMessage;

  CompounderBookingViewModel({
    DatabaseService? databaseService,
    FirebaseFirestore? firestore,
    CompounderPaymentService? paymentService,
  })  : _db = databaseService ?? DatabaseService(),
        _firestore = firestore ?? FirebaseFirestore.instance,
        _paymentService = paymentService ?? CompounderPaymentService();

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
        return '9:15 AM - 1:00 PM';
      case 'afternoon':
        return '2:00 PM - 5:00 PM';
      case 'evening':
        return '6:00 PM - 8:30 PM';
      default:
        return '';
    }
  }

  Future<String> _createNewPatient({
    required String name,
    required String mobile,
    required int age,
    required String aadhaarLast4,
  }) async {
    return _db.createPatientAfterPayment(
      name: name,
      mobileNumber: mobile,
      age: age,
      aadhaarLast4: aadhaarLast4,
    );
  }

  Future<void> _updateExistingPatientVisit(String tokenId) async {
    await _db.updatePatientLastVisited(tokenId);
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

      await _updateExistingPatientVisit(tokenId);
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
    required int age,
    required String aadhaarLast4,
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
      // Check token ID limit before creating new patient
      if (userPhoneNumber != null && userPhoneNumber.isNotEmpty) {
        final tokenCount = await _db.getTokenIdCountForUser(userPhoneNumber);
        if (tokenCount >= 7) {
          _errorMessage =
              'Maximum limit reached! You can create only 7 token IDs per phone number. Please use an existing token ID or contact support.';
          _isProcessing = false;
          notifyListeners();
          throw Exception(_errorMessage);
        }
      }

      final tokenId = await _createNewPatient(
        name: name,
        mobile: mobile,
        age: age,
        aadhaarLast4: aadhaarLast4,
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
        age: age,
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
