import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'dart:async'; // Add this for StreamSubscription
// Assuming you have a UserModel
import '../models/doctor_scheduler.dart'; // To get scheduler stats
import '../utils/appointment_estimator.dart'; // The calculation logic

class PatientAppointmentStatusViewModel extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final AppointmentEstimator _estimator = AppointmentEstimator();
  final DoctorScheduler _scheduler = DoctorScheduler();

  Map<String, dynamic>? _patientAppointment;
  String _waitingStatus = "No active appointments";
  bool _isLoading = true;
  String? _errorMessage;
  StreamSubscription? _appointmentSubscription;
  StreamSubscription? _sessionSubscription;
  bool _isPaused = false;
  List<Map<String, dynamic>> _appointments = [];

  Map<String, dynamic>? get patientAppointment => _patientAppointment;
  String get waitingStatus => _waitingStatus;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<Map<String, dynamic>> get appointments => _appointments;

  // We need to know the current user's ID to fetch their appointment
  String? _currentUserId;

  PatientAppointmentStatusViewModel() {
    _initializeAppointmentListener();
    _setupRealtimeListeners();
  }

  void _setupRealtimeListeners() {
    if (_isPaused) return;

    // Listen to doctor session changes
    _sessionSubscription?.cancel();
    _sessionSubscription = _firestore
        .collection('doctor_sessions')
        .doc('current')
        .snapshots()
        .listen((sessionSnapshot) {
      if (_isPaused) return;
      if (sessionSnapshot.exists) {
        final sessionData = sessionSnapshot.data() as Map<String, dynamic>;
        _handleSessionUpdate(sessionData);
      }
    });

    // Listen to appointments changes
    _appointmentSubscription?.cancel();
    _appointmentSubscription = _firestore
        .collection('appointments')
        .where('appointmentDate',
            isEqualTo: DateFormat('yyyy-MM-dd').format(DateTime.now()))
        .snapshots()
        .listen((appointmentsSnapshot) {
      if (_isPaused) return;
      _handleAppointmentsUpdate(appointmentsSnapshot.docs);
    });
  }

  void _handleSessionUpdate(Map<String, dynamic> sessionData) {
    if (_isPaused) return;
    final isSessionActive = sessionData['isActive'] ?? false;
    final isSessionPaused = sessionData['isPaused'] ?? false;

    if (isSessionPaused) {
      _waitingStatus = "Doctor is currently on break. Please wait.";
    } else if (!isSessionActive) {
      _waitingStatus = "Doctor's session has ended for today.";
    } else {
      _updateWaitingTime();
    }
    notifyListeners();
  }

  void _handleAppointmentsUpdate(List<QueryDocumentSnapshot> appointments) {
    if (_isPaused) return;
    // Update scheduler with latest appointments
    final patientData = appointments.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      // Extract just the start time from the time range string (e.g. "9:15 AM - 1:00 PM" -> "9:15 AM")
      final timeString = data['appointmentTime'].toString();
      final startTime = timeString.split(' - ')[0];
      return {
        'id': doc.id,
        'arrivalTime': startTime,
        'name': (data['patientName'] ?? '').toString(),
        'phone': (data['patientPhone'] ?? '').toString(),
      };
    }).toList();

    _scheduler.addMultiplePatients(patientData);
    _updateWaitingTime();
  }

  void _updateWaitingTime() {
    if (_isPaused || _patientAppointment == null) return;

    final patientId = _patientAppointment!['appointmentId'];
    final patient = Patient(
        patientId, DateTime.parse(_patientAppointment!['appointmentTime']));
    final queuePosition = _scheduler.patients.indexOf(patient) + 1;

    if (_scheduler.isDoctorOnBreak) {
      _waitingStatus =
          "Doctor is on break. Your position in queue: $queuePosition";
    } else if (_scheduler.currentPatient?.id == patientId) {
      _waitingStatus = "You are currently in consultation with the doctor.";
    } else {
      final estimatedWait = _scheduler.averageConsultationTime * queuePosition;
      _waitingStatus =
          "Your estimated waiting time is ${estimatedWait.round()} minutes. Position in queue: $queuePosition";
    }
    notifyListeners();
  }

  void _initializeAppointmentListener() {
    if (_isPaused) return;

    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      _errorMessage = 'User not logged in';
      _isLoading = false;
      notifyListeners();
      return;
    }

    _appointmentSubscription?.cancel();
    _appointmentSubscription = _firestore
        .collection('appointments')
        .where('patientId', isEqualTo: userId)
        .where('status', whereIn: ['pending', 'in_progress'])
        .snapshots()
        .listen((snapshot) {
          if (_isPaused) return;

          try {
            _isLoading = true;
            if (!_isPaused) notifyListeners();

            if (snapshot.docs.isEmpty) {
              _waitingStatus = 'No active appointments';
              _patientAppointment = null;
            } else {
              final appointment = snapshot.docs.first.data();
              _patientAppointment = appointment;

              // Get status from scheduler
              final status = _scheduler.getPatientStatus(userId);
              if (status['status'] == 'success') {
                final data = status['data'];
                final currentStatus =
                    data['currentStatus'] as String? ?? 'Waiting';

                if (currentStatus == 'Waiting') {
                  final queuePosition = data['queuePosition'] as int?;
                  final waitingTime = data['waitingTimeMinutes'] as int?;
                  if (queuePosition != null && waitingTime != null) {
                    _waitingStatus =
                        'Position in queue: $queuePosition\nEstimated wait: $waitingTime minutes';
                  } else {
                    _waitingStatus = 'Waiting for consultation';
                  }
                } else if (currentStatus == 'In Consultation') {
                  _waitingStatus = 'Currently in consultation';
                } else if (currentStatus == 'Completed') {
                  _waitingStatus = 'Consultation completed';
                } else {
                  _waitingStatus = currentStatus;
                }
              } else {
                _waitingStatus = 'Unable to get status';
              }
            }

            _errorMessage = null;
          } catch (e) {
            debugPrint('Error updating appointment status: $e');
            _errorMessage = 'Error updating status: $e';
            _waitingStatus = 'Error getting status';
          } finally {
            _isLoading = false;
            if (!_isPaused) notifyListeners();
          }
        }, onError: (error) {
          if (_isPaused) return;
          debugPrint('Error in appointment listener: $error');
          _errorMessage = 'Error: $error';
          _waitingStatus = 'Error getting status';
          _isLoading = false;
          notifyListeners();
        });
  }

  Future<void> _fetchDoctorSessionAndEstimateTime() async {
    if (_patientAppointment == null) {
      return; // Can't estimate without patient appointment
    }

    _isLoading = true;
    _waitingStatus = "Estimating waiting time...";
    notifyListeners();

    try {
      // Fetch all appointments for today (doctor's view)
      final todayFormatted = DateFormat('yyyy-MM-dd').format(DateTime.now());

      // Note: This query is similar to the doctor's view model, might need composite index
      final allAppointmentsSnapshot = await _firestore
          .collection('appointments')
          .where('appointmentDate', isEqualTo: todayFormatted)
          .orderBy(
              'appointmentTime') // Order by time to get correct queue position
          .get();

      final allAppointments =
          allAppointmentsSnapshot.docs.map((doc) => doc.data()).toList();
      debugPrint(
          '[PatientAppointmentStatusViewModel] Fetched all appointments data: $allAppointments');

      // Fetch doctor's session status
      final sessionDoc =
          await _firestore.collection('doctor_sessions').doc('current').get();
      final sessionData = sessionDoc.data();
      debugPrint(
          '[PatientAppointmentStatusViewModel] Fetched doctor session data: $sessionData');

      final isSessionActive = sessionData?['isActive'] ?? false;
      final isSessionPaused = sessionData?['isPaused'] ?? false;
      final sessionStartTime =
          (sessionData?['startTime'] as Timestamp?)?.toDate();
      final sessionPauseTime =
          (sessionData?['pauseTime'] as Timestamp?)?.toDate();
      // Calculate total break time (requires more sophisticated logic if breaks are intermittent)
      // For simplicity now, assume totalBreakTime is accumulated or calculated on the doctor side.
      // We might need to fetch this from DoctorScheduler stats if available in Firestore.
      // For now, let's assume total break time is tracked in the session document or can be estimated.
      // If session is paused, add duration of current pause to total break time.
      Duration totalBreakDuration = Duration.zero;
      // This part is a simplification. Ideally total break time should be accurately logged.
      // If using the DoctorScheduler stats: fetch doctor user document and read schedulerStats.
      // This requires DoctorScheduler stats to be persisted to Firestore, which they aren't currently.
      // Let's use a placeholder for now and note this needs proper implementation based on how breaks are tracked.

      // ** Simplification Alert **: Assuming total break time is not directly available.
      // A more accurate way would involve logging break start/end times and summing them.
      // For now, we'll rely on the session status and doctor's average time.

      // Re-fetching average consultation time from DoctorAppointmentsViewModel logic would be complex here.
      // Assuming average consultation time is available or can be fetched.
      // If DoctorScheduler stats were in Firestore:
      // final doctorUserDoc = await _firestore.collection('users').doc('DOCTOR_USER_ID').get(); // Need Doctor ID
      // final doctorStats = doctorUserDoc.data()?['schedulerStats'] ?? {};
      // final averageTime = doctorStats['averageConsultationTime'] ?? 5;

      // ** Simplification Alert **: Hardcoding a default average time or assuming it's globally available/fetchabled.
      // Ideally, this should come from the Doctor's persisted scheduler stats.
      const int averageConsultationTime =
          5; // Placeholder - Needs to be fetched correctly

      // If session is paused, calculate the duration of the current pause
      if (isSessionPaused && sessionPauseTime != null) {
        totalBreakDuration += DateTime.now().difference(sessionPauseTime);
      }
      // Add any previously accumulated break time (this is the part that's missing without proper logging)
      // Let's assume for now totalBreakDuration *only* reflects the current pause if any.
      // A real implementation needs total historical break time.

      // Estimate waiting time using the estimator
      _waitingStatus = _estimator.estimateWaitingTime(
        patientAppointmentId: _patientAppointment!['appointmentId'],
        allAppointments: allAppointments,
        sessionStartTime: sessionStartTime,
        isSessionPaused: isSessionPaused,
        sessionPauseTime: sessionPauseTime,
        totalBreakTime: totalBreakDuration, // ** Simplification **
        averageConsultationTime:
            averageConsultationTime, // ** Simplification **
      );

      _errorMessage = null;
    } catch (e) {
      _waitingStatus = "Could not estimate waiting time.";
      _errorMessage = e.toString();
      debugPrint('Error estimating waiting time: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Method to refresh status
  void refreshStatus() {
    _isPaused = false;
    _initializeAppointmentListener();
  }

  // Method to pause the ViewModel
  void pause() {
    _isPaused = true;
    _appointmentSubscription?.cancel();
    _sessionSubscription?.cancel();
  }

  // Method to resume the ViewModel
  void resume() {
    _isPaused = false;
    _initializeAppointmentListener();
    _setupRealtimeListeners();
  }

  @override
  void dispose() {
    _isPaused = true;
    _appointmentSubscription?.cancel();
    _sessionSubscription?.cancel();
    super.dispose();
  }

  Future<void> fetchPatientAppointments(String patientId) async {
    try {
      _isLoading = true;
      notifyListeners();

      final snapshot = await _firestore
          .collection('bookings')
          .where('patientId', isEqualTo: patientId)
          .orderBy('appointmentTime', descending: true)
          .get();

      _appointments = snapshot.docs
          .map((doc) => {
                'id': doc.id,
                ...doc.data(),
              })
          .toList();
    } catch (e) {
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> cancelAppointment(String appointmentId) async {
    try {
      _isLoading = true;
      notifyListeners();

      await _firestore
          .collection('bookings')
          .doc(appointmentId)
          .update({'status': 'cancelled'});

      // Refresh appointments after update
      final appointment =
          _appointments.firstWhere((a) => a['id'] == appointmentId);
      final patientId = appointment['patientId'];
      await fetchPatientAppointments(patientId);
    } catch (e) {
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
