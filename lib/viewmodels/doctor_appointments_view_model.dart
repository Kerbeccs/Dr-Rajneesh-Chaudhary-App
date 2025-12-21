import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/doctor_scheduler.dart';
import 'package:intl/intl.dart';

class DoctorAppointmentsViewModel extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DoctorScheduler _scheduler = DoctorScheduler();

  DateTime? _selectedDate;
  List<Map<String, dynamic>> _appointments = [];
  bool _isLoading = false;
  String? _errorMessage;
  bool _isSessionActive = false;
  bool _isSessionPausedFirebase = false;
  DateTime? _sessionStartTime;
  DateTime? _sessionPauseTime;
  Timer? _timer;
  StreamSubscription? _appointmentsSubscription;
  bool _isPaused = false;

  // New scheduler integration properties
  String? _currentDoctorId;
  Map<String, dynamic>? _schedulerStats;
  Map<String, dynamic>? _queueOverview;
  bool _schedulerInitialized = false;

  // Enhanced consultation time tracking
  final List<double> _consultationTimes = [];
  double _meanConsultationTime = 5.0;
  double _stdDevConsultationTime = 2.0;
  int _completedConsultationsToday = 0;
  DateTime? _lastConsultationTime;

  // Patient flow tracking
  final Map<String, DateTime> _patientStartTimes = {};
  final Map<String, DateTime> _patientArrivalTimes = {};
  int _currentPatientNumber = 0;

  // Automatic time tracking
  DateTime? _lastCompletionTime;
  DateTime? _sessionStartTimeForTracking;

  DateTime? get selectedDate => _selectedDate;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isSessionActive => _isSessionActive;
  bool get isSessionPaused => _isSessionPausedFirebase;
  DateTime? get sessionStartTime => _sessionStartTime;
  Map<String, dynamic> get schedulerStats => _schedulerStats ?? {};
  Map<String, dynamic> get queueOverview => _queueOverview ?? {};
  int get averageConsultationTime =>
      _schedulerStats?['data']?['averageConsultationTime']?.round() ?? 5;
  bool get schedulerInitialized => _schedulerInitialized;
  double get meanConsultationTime => _meanConsultationTime;
  double get stdDevConsultationTime => _stdDevConsultationTime;
  int get completedConsultationsToday => _completedConsultationsToday;
  int get currentPatientNumber => _currentPatientNumber;

  List<Map<String, dynamic>> get appointments => _appointments;

  // Constructor: Initialize without starting listeners
  DoctorAppointmentsViewModel() {
    _initializeSession();
    _selectedDate = DateTime.now();
    _getCurrentDoctorId();
    _loadConsultationStats();
  }

  // Get current doctor ID from Firebase Auth
  Future<void> _getCurrentDoctorId() async {
    final user = _auth.currentUser;
    if (user != null) {
      _currentDoctorId = user.uid;
      await _initializeScheduler();
    }
  }

  // Initialize scheduler with today's appointments
  Future<void> _initializeScheduler() async {
    if (_isPaused || _currentDoctorId == null) return;

    try {
      debugPrint('Initializing scheduler for doctor: $_currentDoctorId');
      final result = await _scheduler.loadTodaysAppointments(_currentDoctorId!);

      if (result['status'] == 'success') {
        _schedulerInitialized = true;
        await _updateSchedulerStats();
        debugPrint('Scheduler initialized successfully: ${result['message']}');
      } else {
        debugPrint('Scheduler initialization failed: ${result['message']}');
        _errorMessage = result['message'];
      }
    } catch (e) {
      debugPrint('Error initializing scheduler: $e');
      _errorMessage = 'Failed to initialize scheduler: $e';
    }

    if (!_isPaused) notifyListeners();
  }

  // Update scheduler statistics
  Future<void> _updateSchedulerStats() async {
    if (_isPaused) return;

    try {
      _schedulerStats = _scheduler.getStats();
      _queueOverview = _scheduler.getQueueOverview();
    } catch (e) {
      debugPrint('Error updating scheduler stats: $e');
    }
  }

  // Method to pause the ViewModel and cancel background tasks
  void pause() {
    debugPrint('DoctorAppointmentsViewModel paused.');
    _isPaused = true;
    _timer?.cancel();
    _timer = null; // Clear the reference to prevent reuse
    _appointmentsSubscription?.cancel();
  }

  // Method to resume the ViewModel and restart background tasks
  void resume() {
    debugPrint('DoctorAppointmentsViewModel resumed.');
    _isPaused = false;
    _initializeSession();
    _startAppointmentsListener();
    if (!_isPaused) notifyListeners();
  }

  void _startAppointmentsListener() {
    if (_isPaused || _selectedDate == null) {
      debugPrint(
          '[_startAppointmentsListener] ViewModel paused or date not selected, not starting listener.');
      return;
    }

    debugPrint(
        '[_startAppointmentsListener] Starting listener for date: ${DateFormat('yyyy-MM-dd').format(_selectedDate!)}');

    final formattedDate = DateFormat('yyyy-MM-dd').format(_selectedDate!);

    _appointmentsSubscription?.cancel();
    _appointmentsSubscription = _firestore
        .collection('appointments')
        .where('appointmentDate', isEqualTo: formattedDate)
        .where('status', whereIn: ['pending', 'in_progress'])
        .snapshots()
        .listen((snapshot) async {
          _safeOperation(() async {
            debugPrint('[_startAppointmentsListener] Received snapshot.');
            try {
              _isLoading = true;
              if (!_isPaused) notifyListeners();

              final appointmentsList = <Map<String, dynamic>>[];

              final patientFutures = snapshot.docs.map((doc) async {
                if (_isPaused) {
                  debugPrint(
                      '[_startAppointmentsListener] ViewModel paused during patient fetch future creation, aborting.');
                  return null;
                }
                final data = doc.data();
                final ownerUserId =
                    data['patientId'] as String?; // owner (logged-in user id)
                final patientToken =
                    data['patientToken'] as String?; // actual patient token id
                if (ownerUserId == null) {
                  debugPrint(
                      '[_startAppointmentsListener] patientId (owner) is null for doc ${doc.id}');
                  return null;
                }

                Map<String, dynamic> patientData = {};
                try {
                  if (patientToken != null) {
                    final patientDoc = await _firestore
                        .collection('patients')
                        .doc(patientToken)
                        .get();
                    patientData = patientDoc.data() ?? {};
                  } else {
                    // Fallback: use user profile if legacy appointment
                    final userDoc = await _firestore
                        .collection('users')
                        .doc(ownerUserId)
                        .get();
                    patientData = userDoc.data() ?? {};
                  }
                } catch (e) {
                  debugPrint('Error fetching patient data: $e');
                }

                if (_isPaused) {
                  debugPrint(
                      '[_startAppointmentsListener] ViewModel paused after patient fetch future completes, aborting.');
                  return null;
                }
                return {
                  'appointmentId': doc.id,
                  'patientId': ownerUserId,
                  'patientToken': patientToken,
                  'patientData': patientData,
                  'appointmentData': data,
                };
              }).toList();

              final results = await Future.wait(patientFutures
                  .where((future) => future != null)
                  .map((future) => future as Future<Map<String, dynamic>?>));

              final validResults = results
                  .where((result) => result != null)
                  .cast<Map<String, dynamic>>();

              if (_isPaused) {
                debugPrint(
                    '[_startAppointmentsListener] ViewModel paused after Future.wait, aborting.');
                return;
              }

              // Process results and build appointments list with scheduler predictions
              for (var result in validResults) {
                final data = result['appointmentData'];
                final patientData = result['patientData'];
                final patientId = result['patientId'];

                // Get waiting time estimation from scheduler
                Map<String, dynamic>? waitingTimeInfo;
                if (_schedulerInitialized) {
                  try {
                    waitingTimeInfo =
                        _scheduler.estimateWaitingTimeById(patientId);
                  } catch (e) {
                    debugPrint(
                        'Error getting waiting time for patient $patientId: $e');
                  }
                }

                // Prefer scheduler predictions; fallback to persisted Firestore fields
                final schedulerWaitingMinutes =
                    waitingTimeInfo?['data']?['waitingTimeMinutes'];
                final schedulerQueuePos =
                    waitingTimeInfo?['data']?['queuePosition'];

                appointmentsList.add({
                  'appointmentId': result['appointmentId'],
                  'patientId': result['patientId'],
                  'patientToken': result['patientToken'],
                  'patientName': (patientData['name'] as String?) ??
                      patientData['patientName'] as String? ??
                      data['patientName'] as String? ??
                      'N/A',
                  'patientPhone': (patientData['mobileNumber'] as String?) ??
                      (patientData['phoneNumber'] as String?) ??
                      'N/A',
                  'patientEmail': patientData['email'] as String? ?? 'N/A',
                  'slotNumber': data['seatNumber'] as int?,
                  'date': data['appointmentDate'] as String?,
                  'time': data['appointmentTime'] as String?,
                  'status': data['status'] as String? ?? 'N/A',
                  'createdAt': (data['createdAt'] as Timestamp?)?.toDate(),
                  // Add scheduler predictions
                  'waitingTimeMinutes': schedulerWaitingMinutes ??
                      (data['estimatedWaitTime'] is num
                          ? (data['estimatedWaitTime'] as num).toDouble()
                          : null),
                  'queuePosition': schedulerQueuePos ??
                      (data['queuePosition'] is int
                          ? data['queuePosition']
                          : null),
                  'estimatedCallTime': waitingTimeInfo?['data']
                      ?['estimatedCallTime'],
                  'consultationStatus': waitingTimeInfo?['status'],
                });
              }

              appointmentsList.sort((a, b) => (a['time'] as String? ?? '')
                  .compareTo(b['time'] as String? ?? ''));

              _appointments = appointmentsList;
              _errorMessage = null;
              await _updateSchedulerStats(); // Update stats after processing appointments
              debugPrint(
                  '[_startAppointmentsListener] Data processed, found ${_appointments.length} appointments.');
            } catch (e) {
              debugPrint(
                  '[_startAppointmentsListener] Error processing appointments: $e');
              _errorMessage = 'Failed to load appointments: $e';
            } finally {
              _isLoading = false;
              if (!_isPaused) notifyListeners();
            }
          });
        }, onError: (error) {
          _safeOperation(() {
            debugPrint('[_startAppointmentsListener] Stream error: $error');
            _isLoading = false;
            _errorMessage = 'Error fetching appointments: $error';
            if (!_isPaused) notifyListeners();
          });
        });
  }

  Future<void> _initializeSession() async {
    if (_isPaused) return;
    try {
      final sessionDoc =
          await _firestore.collection('doctor_sessions').doc('current').get();

      if (sessionDoc.exists) {
        final data = sessionDoc.data() as Map<String, dynamic>;
        _isSessionActive = data['isActive'] ?? false;
        _isSessionPausedFirebase = data['isPaused'] ?? false;
        _sessionStartTime = (data['startTime'] as Timestamp?)?.toDate();
        _sessionPauseTime = (data['pauseTime'] as Timestamp?)?.toDate();

        if (_isSessionActive && !_isSessionPausedFirebase && _timer == null) {
          _startTimer();
        }
      }
      if (!_isPaused) notifyListeners();
    } catch (e) {
      print('Error initializing session: $e');
      _errorMessage = 'Error initializing session: $e';
      if (!_isPaused) notifyListeners();
    }
  }

  void _startTimer() {
    if (_isPaused) return;
    _timer?.cancel();
    _timer = null; // Clear reference before creating new timer
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isPaused || !_isSessionActive) {
        timer.cancel();
        _timer = null;
        return;
      }
      notifyListeners();
    });
  }

  Future<void> _updateSessionInFirestore() async {
    if (_isPaused) return;
    try {
      await _firestore.collection('doctor_sessions').doc('current').set({
        'isActive': _isSessionActive,
        'isPaused': _isSessionPausedFirebase,
        'startTime': _sessionStartTime,
        'pauseTime': _sessionPauseTime,
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      print('Error updating session in Firestore: $e');
    }
  }

  List<DateTime> get availableDates {
    final today = DateTime.now();
    return [today, today.add(const Duration(days: 1))];
  }

  void selectDate(DateTime date) {
    if (_isPaused) return;
    if (_selectedDate?.year == date.year &&
        _selectedDate?.month == date.month &&
        _selectedDate?.day == date.day) {
      return;
    }

    _selectedDate = date;
    _startAppointmentsListener();
    if (!_isPaused) notifyListeners();
  }

  // Add new methods for consultation tracking
  Future<void> _loadConsultationStats() async {
    if (_isPaused || _currentDoctorId == null) return;

    try {
      final statsDoc = await _firestore
          .collection('doctor_stats')
          .doc(_currentDoctorId)
          .get();

      if (statsDoc.exists) {
        final data = statsDoc.data() as Map<String, dynamic>;
        _meanConsultationTime = data['meanConsultationTime']?.toDouble() ?? 5.0;
        _stdDevConsultationTime =
            data['stdDevConsultationTime']?.toDouble() ?? 2.0;
        _completedConsultationsToday =
            data['completedConsultationsToday']?.toInt() ?? 0;
      }
    } catch (e) {
      debugPrint('Error loading consultation stats: $e');
    }
  }

  Future<void> _saveConsultationStats() async {
    if (_isPaused || _currentDoctorId == null) return;

    try {
      await _firestore.collection('doctor_stats').doc(_currentDoctorId).set({
        'meanConsultationTime': _meanConsultationTime,
        'stdDevConsultationTime': _stdDevConsultationTime,
        'completedConsultationsToday': _completedConsultationsToday,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error saving consultation stats: $e');
    }
  }

  void _updateConsultationStatistics(double newConsultationTime) {
    _consultationTimes.add(newConsultationTime);

    // Update mean and standard deviation
    final n = _consultationTimes.length;
    final mean = _consultationTimes.reduce((a, b) => a + b) / n;
    final sumSqDiff = _consultationTimes
        .map((time) => math.pow(time - mean, 2))
        .reduce((a, b) => a + b);
    final stdDev = math.sqrt(sumSqDiff / n);

    _meanConsultationTime = mean;
    _stdDevConsultationTime = stdDev;

    debugPrint(
        'Updated consultation stats - Mean: $_meanConsultationTime, StdDev: $_stdDevConsultationTime');
  }

  // Update waiting time calculation - DEPRECATED: Use _updateQueuePositions instead
  Map<String, dynamic> calculateWaitingTimeForPatient(int patientSlotNumber) {
    // This method is deprecated and inconsistent with _updateQueuePositions
    // The correct logic is in _updateQueuePositions which sorts by slot number
    debugPrint(
        '[calculateWaitingTimeForPatient] DEPRECATED: This method uses inconsistent logic');
    final queuePosition = patientSlotNumber - _currentPatientNumber;
    final waitingTime =
        queuePosition > 0 ? queuePosition * _meanConsultationTime : 0;
    final estimatedCallTime =
        DateTime.now().add(Duration(minutes: waitingTime.round()));

    return {
      'waitingTimeMinutes': waitingTime,
      'queuePosition': queuePosition,
      'estimatedCallTime': estimatedCallTime,
      'status': waitingTime > 0 ? 'waiting' : 'in_progress',
    };
  }

  // ENHANCED: Mark appointment complete with scheduler integration
  Future<void> markAppointmentComplete(String appointmentId,
      {int? actualConsultationMinutes}) async {
    if (_isPaused) return;
    try {
      _isLoading = true;
      if (!_isPaused) notifyListeners();

      final appointmentDoc =
          await _firestore.collection('appointments').doc(appointmentId).get();

      if (!appointmentDoc.exists) {
        throw Exception('Appointment not found');
      }

      final appointmentData = appointmentDoc.data()!;
      final patientId = appointmentData['patientId'] as String?;

      if (patientId == null) {
        throw Exception('Patient ID not found in appointment data');
      }

      // Calculate consultation time
      int consultationTime =
          actualConsultationMinutes ?? 5; // Default to 5 minutes

      if (actualConsultationMinutes == null) {
        final appointmentStartTime =
            (appointmentData['createdAt'] as Timestamp?)?.toDate() ??
                _sessionStartTime;
        consultationTime = appointmentStartTime != null
            ? DateTime.now().difference(appointmentStartTime).inMinutes.abs()
            : 5;
      }

      // Update scheduler first
      Map<String, dynamic>? schedulerResult;
      if (_schedulerInitialized) {
        try {
          schedulerResult =
              await _scheduler.markAsCompleted(patientId, consultationTime);
          debugPrint('Scheduler mark complete result: $schedulerResult');
        } catch (e) {
          debugPrint('Error updating scheduler: $e');
        }
      }

      // Update Firestore
      await _firestore.collection('appointments').doc(appointmentId).update({
        'status': 'completed',
        'completedAt': FieldValue.serverTimestamp(),
        'consultationDurationMinutes': consultationTime,
      });

      await _firestore.collection('users').doc(patientId).update({
        'appointmentStatus': 'completed',
        'lastVisited': DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()),
      });

      // Calculate actual time spent automatically
      int actualConsultationTime;
      final now = DateTime.now();

      if (actualConsultationMinutes != null) {
        // Use provided consultation time (manual override)
        actualConsultationTime = actualConsultationMinutes;
        debugPrint(
            '[Time Calculation] Using provided consultation time: $actualConsultationTime minutes');
      } else if (_lastCompletionTime != null) {
        // Calculate time since last completion
        final diff = now.difference(_lastCompletionTime!).inMinutes;
        actualConsultationTime = diff > 0 ? diff : 1; // At least 1 minute
        debugPrint(
            '[Time Calculation] Time since last completion: $actualConsultationTime minutes');
      } else if (_sessionStartTimeForTracking != null) {
        // First patient: calculate from session start
        final diff = now.difference(_sessionStartTimeForTracking!).inMinutes;
        actualConsultationTime =
            diff > 0 ? diff : 5; // Default 5 minutes for first patient
        debugPrint(
            '[Time Calculation] First patient, time from session start: $actualConsultationTime minutes');
      } else {
        // Fallback: use 5 minutes as default
        actualConsultationTime = 5;
        debugPrint(
            '[Time Calculation] No tracking data, using 5 minute default');
      }

      // Update last completion time for next calculation
      _lastCompletionTime = now;

      // Update statistics
      _updateConsultationStatistics(actualConsultationTime.toDouble());
      _completedConsultationsToday++;
      _currentPatientNumber++; // Increment current patient number after completion

      // Write consultation_times record for analytics
      if (_currentDoctorId != null) {
        final consRef = _firestore.collection('consultation_times').doc();
        await consRef.set({
          'consultationId': consRef.id,
          'date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
          'doctorId': _currentDoctorId,
          'patientId': patientId,
          'appointmentId': appointmentId,
          'actualConsultationTime': actualConsultationTime,
          'startTime': appointmentData['consultationStartTime'],
          'endTime': FieldValue.serverTimestamp(),
          'sessionId':
              '${DateFormat('yyyy-MM-dd').format(DateTime.now())}_$_currentDoctorId',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      // Update queue_sessions rolling average and counters
      if (_currentDoctorId != null) {
        final sessionId =
            '${DateFormat('yyyy-MM-dd').format(DateTime.now())}_$_currentDoctorId';
        await _firestore.collection('queue_sessions').doc(sessionId).set({
          'averageConsultationTime': _meanConsultationTime,
          'totalConsultationsCompleted': _completedConsultationsToday,
          'currentPatientNumber': _currentPatientNumber,
          'lastUpdated': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      // Refresh appointments list to get latest status before updating queue positions
      await refreshAppointments();

      // Update queue positions for remaining patients
      await _updateQueuePositions();

      // Notify patients of updated wait times
      await _notifyWaitingPatients();

      // Force refresh patient tickets by updating a signal document
      if (_currentDoctorId != null) {
        await _firestore.collection('queue_updates').doc('latest').set({
          'lastUpdate': FieldValue.serverTimestamp(),
          'doctorId': _currentDoctorId,
          'completedAppointmentId': appointmentId,
          'currentPatientNumber': _currentPatientNumber,
          'meanConsultationTime': _meanConsultationTime,
        });
      }

      // Save updated stats to Firestore
      await _saveConsultationStats();

      // Update scheduler stats and refresh appointments
      await _updateSchedulerStats();
      await refreshAppointments();

      debugPrint('Appointment $appointmentId completed successfully');
      if (schedulerResult != null && schedulerResult['status'] == 'success') {
        debugPrint(
            'New average consultation time: ${schedulerResult['data']['newAverage']} minutes');
      }
    } catch (e) {
      debugPrint("Error marking appointment complete: $e");
      _errorMessage = "Failed to update appointment: $e";
      if (!_isPaused) notifyListeners();
    } finally {
      _isLoading = false;
      if (!_isPaused) notifyListeners();
    }
  }

  // NEW: Start consultation for a patient
  Future<Map<String, dynamic>?> startConsultation(String appointmentId) async {
    if (_isPaused || !_schedulerInitialized) return null;

    try {
      final appointmentDoc =
          await _firestore.collection('appointments').doc(appointmentId).get();
      if (!appointmentDoc.exists) {
        throw Exception('Appointment not found');
      }

      final appointmentData = appointmentDoc.data()!;
      final patientId = appointmentData['patientId'] as String?;

      if (patientId == null) {
        throw Exception('Patient ID not found in appointment data');
      }

      // Start consultation in scheduler
      final result = await _scheduler.startConsultation(patientId);

      if (result['status'] == 'success') {
        // Update appointment status in Firestore
        await _firestore.collection('appointments').doc(appointmentId).update({
          'status': 'in_progress',
          'consultationStatus': 'in_consultation',
          'consultationStartTime': FieldValue.serverTimestamp(),
        });

        // Track patient flow
        _patientStartTimes[patientId] = DateTime.now();
        _currentPatientNumber++;

        await _updateSchedulerStats();
        if (!_isPaused) notifyListeners();

        debugPrint(
            'Consultation started for patient: ${result['data']['patientName']}');
      }

      return result;
    } catch (e) {
      debugPrint('Error starting consultation: $e');
      return {
        'status': 'error',
        'message': 'Failed to start consultation: $e',
        'data': null
      };
    }
  }

  // NEW: Pause doctor session with scheduler integration
  Future<Map<String, dynamic>?> pauseDoctorSession(String reason) async {
    if (_isPaused || !_schedulerInitialized) return null;

    try {
      // Pause in scheduler first
      final result = _scheduler.pauseDoctor(reason);

      if (result['status'] == 'success') {
        // Pause Firebase session
        await pauseSession();
        await _updateSchedulerStats();

        debugPrint('Doctor session paused: $reason');
      }

      return result;
    } catch (e) {
      debugPrint('Error pausing doctor session: $e');
      return {
        'status': 'error',
        'message': 'Failed to pause session: $e',
        'data': null
      };
    }
  }

  // NEW: Resume doctor session with scheduler integration
  Future<Map<String, dynamic>?> resumeDoctorSession() async {
    if (_isPaused || !_schedulerInitialized) return null;

    try {
      // Resume in scheduler first
      final result = _scheduler.resumeDoctor(); // <-- await here

      if (result['status'] == 'success') {
        // Resume Firebase session
        await resumeSession();
        await _updateSchedulerStats();

        debugPrint('Doctor session resumed');
      }

      return result;
    } catch (e) {
      debugPrint('Error resuming doctor session: $e');
      return {
        'status': 'error',
        'message': 'Failed to resume session: $e',
        'data': null
      };
    }
  }

  // NEW: Get patient waiting time estimation
  Map<String, dynamic>? getPatientWaitingTime(String patientId) {
    if (!_schedulerInitialized) return null;

    try {
      return _scheduler.estimateWaitingTimeById(patientId);
    } catch (e) {
      debugPrint('Error getting patient waiting time: $e');
      return null;
    }
  }

  // NEW: Get all patients status
  Map<String, dynamic>? getAllPatientsStatus() {
    if (!_schedulerInitialized) return null;

    try {
      return _scheduler.getAllPatients();
    } catch (e) {
      debugPrint('Error getting all patients: $e');
      return null;
    }
  }

  Future<void> startSession() async {
    if (_isPaused || _isSessionActive) return;

    final today = DateTime.now();
    if (_selectedDate == null ||
        _selectedDate!.year != today.year ||
        _selectedDate!.month != today.month ||
        _selectedDate!.day != today.day) {
      _errorMessage = "Session can only be started for today's appointments";
      if (!_isPaused) notifyListeners();
      return;
    }

    _isSessionActive = true;
    _isSessionPausedFirebase = false;
    _sessionStartTime = DateTime.now();
    _sessionPauseTime = null;

    // Initialize automatic time tracking
    _sessionStartTimeForTracking = DateTime.now();
    _lastCompletionTime = null;

    // Signal to patients that doctor has started seeing patients
    await _firestore.collection('doctor_sessions').doc('current').set({
      'isActive': true,
      'isPaused': false,
      'startTime': _sessionStartTime,
      'pauseTime': null,
      'currentPatientNumber': _currentPatientNumber,
      'doctorStartedSeeing': true, // NEW: Signal that doctor started
      'sessionDate': DateFormat('yyyy-MM-dd').format(today),
      'lastUpdated': FieldValue.serverTimestamp(),
    });

    // Create or update a daily queue session document for this doctor
    if (_currentDoctorId != null) {
      final sessionId =
          '${DateFormat('yyyy-MM-dd').format(today)}_$_currentDoctorId';
      await _firestore.collection('queue_sessions').doc(sessionId).set({
        'sessionId': sessionId,
        'date': DateFormat('yyyy-MM-dd').format(today),
        'doctorId': _currentDoctorId,
        'sessionStartTime': FieldValue.serverTimestamp(),
        'sessionEndTime': null,
        'isActive': true,
        'currentPatientNumber': _currentPatientNumber,
        'averageConsultationTime': _meanConsultationTime,
        'totalConsultationsCompleted': _completedConsultationsToday,
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    _startTimer();
    if (!_schedulerInitialized && _currentDoctorId != null) {
      await _initializeScheduler();
    }
    if (!_isPaused) notifyListeners();
  }

  Future<void> pauseSession() async {
    if (_isPaused || !_isSessionActive || _isSessionPausedFirebase) return;

    _isSessionPausedFirebase = true;
    _sessionPauseTime = DateTime.now();

    await _updateSessionInFirestore();
    _timer?.cancel();
    _timer = null; // Clear reference
    if (!_isPaused) notifyListeners();
  }

  Future<void> resumeSession() async {
    if (_isPaused || !_isSessionActive || !_isSessionPausedFirebase) return;

    _isSessionPausedFirebase = false;
    _sessionPauseTime = null;

    await _updateSessionInFirestore();
    _startTimer();
    if (!_isPaused) notifyListeners();
  }

  Future<void> resetSession() async {
    if (_isPaused) return;
    _isSessionActive = false;
    _isSessionPausedFirebase = false;
    _sessionStartTime = null;
    _sessionPauseTime = null;

    // Reset automatic time tracking
    _lastCompletionTime = null;
    _sessionStartTimeForTracking = null;

    await _updateSessionInFirestore();
    _timer?.cancel();
    _timer = null; // Clear reference
    if (!_isPaused) notifyListeners();
  }

  // Helper to calculate actual consultation time from appointment data
  int _calculateActualConsultationTime(Map<String, dynamic> appointmentData) {
    // Try to get consultation start time
    final consultationStart =
        (appointmentData['consultationStartTime'] as Timestamp?)?.toDate();

    // If no consultation start time, use appointment creation time as fallback
    final appointmentStart =
        (appointmentData['createdAt'] as Timestamp?)?.toDate();

    final start = consultationStart ?? appointmentStart ?? _sessionStartTime;
    final end = DateTime.now();

    if (start != null) {
      final diff = end.difference(start).inMinutes;
      debugPrint(
          '[Time Calculation] Start: $start, End: $end, Diff: $diff minutes');

      // Use actual time if reasonable (1-60 minutes), otherwise fallback
      if (diff > 0 && diff <= 60) {
        return diff;
      } else if (diff > 60) {
        debugPrint(
            '[Time Calculation] Consultation too long ($diff min), using 5 min fallback');
        return 5; // Cap at 5 minutes for very long consultations
      } else {
        debugPrint(
            '[Time Calculation] Negative time difference, using 1 min fallback');
        return 1; // Use 1 minute for negative time
      }
    }

    debugPrint('[Time Calculation] No start time found, using 1 min fallback');
    return 1; // Use 1 minute as default instead of 5
  }

  @override
  void dispose() {
    debugPrint('DoctorAppointmentsViewModel disposed.');
    _isPaused = true;
    _timer?.cancel();
    _timer = null; // Clear reference
    _appointmentsSubscription?.cancel();
    _appointmentsSubscription = null; // Clear reference
    _scheduler.dispose(); // Dispose scheduler
    super.dispose();
  }

  String getSessionDuration() {
    if (_isPaused || !_isSessionActive || _sessionStartTime == null) {
      return '00:00:00';
    }

    final now = DateTime.now();
    final duration = _isSessionPausedFirebase
        ? _sessionPauseTime!.difference(_sessionStartTime!)
        : now.difference(_sessionStartTime!);

    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');

    return '$hours:$minutes:$seconds';
  }

  void _safeOperation(Function() operation) {
    if (!_isPaused) {
      operation();
    } else {
      debugPrint('Operation cancelled: ViewModel paused.');
    }
  }

  Future<void> refreshAppointments() async {
    if (_isPaused) return;
    debugPrint(
        '[refreshAppointments] Fetching appointments for date: ${DateFormat('yyyy-MM-dd').format(_selectedDate!)}');

    _safeOperation(() async {
      if (_isPaused) {
        debugPrint(
            '[refreshAppointments] ViewModel paused, returning from safe operation.');
        return;
      }

      try {
        _isLoading = true;
        if (!_isPaused) notifyListeners();

        final formattedDate = DateFormat('yyyy-MM-dd').format(_selectedDate!);

        if (_isPaused) {
          debugPrint(
              '[refreshAppointments] ViewModel paused before Firestore get, aborting.');
          return;
        }

        final snapshot = await _firestore
            .collection('appointments')
            .where('appointmentDate', isEqualTo: formattedDate)
            .where('status', whereIn: ['pending', 'in_progress']).get();

        if (_isPaused) {
          debugPrint(
              '[refreshAppointments] ViewModel paused after Firestore get, aborting.');
          return;
        }

        final appointmentsList = <Map<String, dynamic>>[];

        final patientFutures = snapshot.docs.map((doc) async {
          if (_isPaused) {
            debugPrint(
                '[refreshAppointments] ViewModel paused during patient fetch future creation, aborting.');
            return null;
          }
          final data = doc.data();
          final ownerUserId = data['patientId'] as String?; // owner
          final patientToken = data['patientToken'] as String?; // token
          if (ownerUserId == null) {
            debugPrint(
                '[refreshAppointments] patientId is null for doc ${doc.id}');
            return null;
          }
          Map<String, dynamic> patientData = {};
          try {
            if (patientToken != null) {
              final pDoc = await _firestore
                  .collection('patients')
                  .doc(patientToken)
                  .get();
              patientData = pDoc.data() ?? {};
            } else {
              final userDoc =
                  await _firestore.collection('users').doc(ownerUserId).get();
              patientData = userDoc.data() ?? {};
            }
          } catch (e) {
            debugPrint('Error fetching patient data: $e');
          }
          if (_isPaused) {
            debugPrint(
                '[refreshAppointments] ViewModel paused after patient fetch future completes, aborting.');
            return null;
          }
          return {
            'appointmentId': doc.id,
            'patientId': ownerUserId,
            'patientToken': patientToken,
            'patientData': patientData,
            'appointmentData': data,
          };
        }).toList();

        final results = await Future.wait(patientFutures
            .where((future) => future != null)
            .map((future) => future as Future<Map<String, dynamic>?>));

        final validResults = results
            .where((result) => result != null)
            .cast<Map<String, dynamic>>();

        if (_isPaused) {
          debugPrint(
              '[refreshAppointments] ViewModel paused after Future.wait, aborting.');
          return;
        }

        // Process results and build appointments list with scheduler data
        for (var result in validResults) {
          final data = result['appointmentData'];
          final patientData = result['patientData'];
          final patientId = result['patientId'];

          // Get waiting time estimation from scheduler
          Map<String, dynamic>? waitingTimeInfo;
          if (_schedulerInitialized) {
            try {
              waitingTimeInfo = _scheduler.estimateWaitingTimeById(patientId);
            } catch (e) {
              debugPrint(
                  'Error getting waiting time for patient $patientId: $e');
            }
          }

          // Prefer scheduler predictions; fallback to persisted Firestore fields
          final schedulerWaitingMinutes =
              waitingTimeInfo?['data']?['waitingTimeMinutes'];
          final schedulerQueuePos = waitingTimeInfo?['data']?['queuePosition'];

          appointmentsList.add({
            'appointmentId': result['appointmentId'],
            'patientId': result['patientId'],
            'patientToken': result['patientToken'],
            'patientName': (patientData['name'] as String?) ??
                patientData['patientName'] as String? ??
                data['patientName'] as String? ??
                'N/A',
            'patientPhone': (patientData['mobileNumber'] as String?) ??
                (patientData['phoneNumber'] as String?) ??
                'N/A',
            'patientEmail': patientData['email'] as String? ?? 'N/A',
            'slotNumber': data['seatNumber'] as int?,
            'date': data['appointmentDate'] as String?,
            'time': data['appointmentTime'] as String?,
            'status': data['status'] as String? ?? 'N/A',
            'createdAt': (data['createdAt'] as Timestamp?)?.toDate(),
            // Add scheduler predictions
            'waitingTimeMinutes': schedulerWaitingMinutes ??
                (data['estimatedWaitTime'] is num
                    ? (data['estimatedWaitTime'] as num).toDouble()
                    : null),
            'queuePosition': schedulerQueuePos ??
                (data['queuePosition'] is int ? data['queuePosition'] : null),
            'estimatedCallTime': waitingTimeInfo?['data']?['estimatedCallTime'],
            'consultationStatus': waitingTimeInfo?['status'],
          });
        }

        appointmentsList.sort((a, b) =>
            (a['time'] as String? ?? '').compareTo(b['time'] as String? ?? ''));

        _appointments = appointmentsList;
        _errorMessage = null;

        // Refresh scheduler data if needed
        if (_schedulerInitialized && _currentDoctorId != null) {
          await _scheduler.refreshAppointments(_currentDoctorId!);
          await _updateSchedulerStats();
        }

        debugPrint(
            '[refreshAppointments] Data processed, found ${_appointments.length} appointments.');
      } catch (e) {
        debugPrint('[refreshAppointments] Error refreshing appointments: $e');
        _errorMessage = 'Failed to refresh appointments: $e';
      } finally {
        _isLoading = false;
        if (!_isPaused) notifyListeners();
      }
    });
  }

  Future<void> fetchDoctorAppointments(String doctorId) async {
    try {
      _isLoading = true;
      notifyListeners();

      final snapshot = await _firestore
          .collection('bookings')
          .where('doctorId', isEqualTo: doctorId)
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

  Future<void> updateAppointmentStatus(
      String appointmentId, String status) async {
    try {
      _isLoading = true;
      notifyListeners();

      await _firestore
          .collection('bookings')
          .doc(appointmentId)
          .update({'status': status});

      final appointment =
          _appointments.firstWhere((a) => a['id'] == appointmentId);
      final doctorId = appointment['doctorId'];
      await fetchDoctorAppointments(doctorId);
    } catch (e) {
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // New helper methods
  Future<void> _updateQueuePositions() async {
    debugPrint('[_updateQueuePositions] Starting queue position update...');
    debugPrint(
        '[_updateQueuePositions] Current appointments count: ${_appointments.length}');

    // Build sorted queue by slot number for consistent positions
    final remaining = _appointments
        .where((apt) =>
            (apt['status'] == 'pending' || apt['status'] == 'in_progress'))
        .toList();

    debugPrint(
        '[_updateQueuePositions] Remaining appointments: ${remaining.length}');
    for (final apt in remaining) {
      debugPrint(
          '[_updateQueuePositions] - ${apt['appointmentId']}: seat ${apt['slotNumber']}, status: ${apt['status']}');
    }

    remaining.sort((a, b) =>
        (a['slotNumber'] as int?)?.compareTo((b['slotNumber'] as int?) ?? 0) ??
        0);

    // Compute positions where first in list is position=1 ("You're next")
    final List<_QueueUpdate> updates = [];
    for (int i = 0; i < remaining.length; i++) {
      final appt = remaining[i];
      final position = i + 1; // 1-based
      final waitMinutes =
          position > 1 ? (position - 1) * _meanConsultationTime : 0.0;
      debugPrint(
          '[_updateQueuePositions] Position $position: ${appt['appointmentId']} -> $waitMinutes min wait');
      updates.add(_QueueUpdate(
        appointmentId: appt['appointmentId'] as String,
        queuePosition: position,
        estimatedWaitTime: waitMinutes,
      ));
    }

    debugPrint(
        '[_updateQueuePositions] Total updates to process: ${updates.length}');

    // Batch write in chunks of 450 to stay under the 500 limit comfortably
    const int chunkSize = 450;
    for (int i = 0; i < updates.length; i += chunkSize) {
      final batch = _firestore.batch();
      final chunk = updates.skip(i).take(chunkSize);
      debugPrint(
          '[_updateQueuePositions] Processing batch ${i ~/ chunkSize + 1} with ${chunk.length} updates');
      for (final u in chunk) {
        final ref = _firestore.collection('appointments').doc(u.appointmentId);
        batch.update(ref, {
          'estimatedWaitTime': u.estimatedWaitTime,
          'queuePosition': u.queuePosition,
          'lastUpdated': FieldValue.serverTimestamp(),
        });

        // Mirror into patient_queue for patient-side reading
        final appt = remaining.firstWhere(
          (a) => a['appointmentId'] == u.appointmentId,
          orElse: () => {},
        );
        if (appt.isNotEmpty) {
          final dateStr = (appt['date'] as String?) ??
              DateFormat('yyyy-MM-dd').format(DateTime.now());
          final pqId = '${dateStr}_${u.appointmentId}';
          debugPrint(
              '[_updateQueuePositions] Writing to patient_queue: $pqId -> position ${u.queuePosition}, wait ${u.estimatedWaitTime}');
          final pqRef = _firestore.collection('patient_queue').doc(pqId);
          batch.set(
            pqRef,
            {
              'queueId': pqId,
              'date': dateStr,
              'appointmentId': u.appointmentId,
              'patientId': appt['patientId'],
              'patientToken': appt['patientToken'],
              'doctorId': _currentDoctorId,
              'seatNumber': appt['slotNumber'],
              'queuePosition': u.queuePosition,
              'estimatedWaitTime': u.estimatedWaitTime,
              'status': appt['status'],
              'lastUpdated': FieldValue.serverTimestamp(),
              'createdAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }
      }
      await batch.commit();
      debugPrint(
          '[_updateQueuePositions] Batch ${i ~/ chunkSize + 1} committed successfully');
    }
    debugPrint('[_updateQueuePositions] Queue position update completed');
  }

  Future<void> _notifyWaitingPatients() async {
    // Optional: send notifications (kept as no-op for now)
  }
}

// Lightweight internal struct to carry queue updates
class _QueueUpdate {
  final String appointmentId;
  final int queuePosition;
  final double estimatedWaitTime;
  _QueueUpdate({
    required this.appointmentId,
    required this.queuePosition,
    required this.estimatedWaitTime,
  });
}
