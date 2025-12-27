import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import '../models/doctor_scheduler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'dart:math';
import '../utils/locator.dart'; // Import DI locator

class TicketViewModel extends ChangeNotifier {
  final DoctorScheduler _scheduler = DoctorScheduler();
  // Use dependency injection to get shared FirebaseFirestore instance
  final FirebaseFirestore _firestore;
  final String userId;

  // Basic info
  String patientName = 'Loading...';
  String doctorName = "Dr. Rajneesh Chaudhary";
  List<Map<String, dynamic>> bookedSlots = [];
  bool isExpanded = false;
  String waitingTime = "Calculating...";
  double averageConsultationTime = 0.0;
  bool isLoading = false;

  // Enhanced caching and error handling
  final Map<String, Map<String, dynamic>> _cachedStatuses =
      {}; // Cache per appointment
  final Map<String, DateTime> _lastFetchTimes =
      {}; // Last fetch time per appointment
  static const _cacheDuration = Duration(seconds: 30);
  static const _maxRetries = 3;
  final Map<String, int> _retryCounts = {}; // Retry count per appointment
  String? _errorMessage;

  // NEW: Enhanced scheduler integration
  final Map<String, Map<String, dynamic>> _schedulerEstimates =
      {}; // Scheduler estimates per appointment
  final Map<String, DateTime> _estimatesFetchTimes =
      {}; // Last fetch time for estimates
  bool _schedulerInitialized = false;
  String? _currentDoctorId;

  // Timers and subscriptions
  Timer? _timer;
  Timer? _refreshTimer;
  Timer? _schedulerRefreshTimer; // NEW: Timer for scheduler data refresh
  Timer? _debounceTimer; // NEW: Debounce timer to prevent excessive updates
  StreamSubscription? _sessionSubscription;
  StreamSubscription? _appointmentsSubscription;
  StreamSubscription?
      _doctorSessionSubscription; // NEW: Listen to doctor session changes
  StreamSubscription? _queueUpdateSubscription; // NEW: Listen to queue updates
  bool _isDisposed = false;

  // --- NEW: Doctor stats for today ---
  int completedConsultationsToday = 0;
  String todayDate = DateFormat('yyyy-MM-dd').format(DateTime.now());

  // --- NEW: Real-time listeners for appointment status ---
  final Map<String, StreamSubscription<DocumentSnapshot>>
      _appointmentStatusSubscriptions = {};

  // Add session tracking
  bool _isDoctorSeeing = false;
  String _doctorStatus = 'Not started';
  DateTime? _sessionStartTime;

  // Constructor with optional parameter for testing
  TicketViewModel({
    required this.userId,
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? locator<FirebaseFirestore>() {
    _loadPatientData();
    _startSessionListener();
    _startAppointmentsListener();
    _startRefreshTimer();
    _initializeSchedulerIntegration(); // NEW: Initialize scheduler integration
  }

  // NEW: Initialize scheduler integration
  Future<void> _initializeSchedulerIntegration() async {
    try {
      // Get current doctor ID (you might need to adjust this based on your app structure)
      await _getCurrentDoctorId();

      if (_currentDoctorId != null) {
        _schedulerInitialized = true;
        _startDoctorSessionListener();
        _startSchedulerRefreshTimer();
        debugPrint(
            'Scheduler integration initialized for doctor: $_currentDoctorId');
      }
    } catch (e) {
      debugPrint('Error initializing scheduler integration: $e');
    }
  }

  // NEW: Get current doctor ID (adjust this method based on your app's doctor-patient relationship)
  Future<void> _getCurrentDoctorId() async {
    try {
      // Option 1: If doctor ID is stored in user document
      final userDoc = await _firestore.collection('users').doc(userId).get();
      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;
        _currentDoctorId = userData['assignedDoctorId'] ?? userData['doctorId'];
      }

      // Option 2: If you need to get it from appointments
      if (_currentDoctorId == null && bookedSlots.isNotEmpty) {
        final appointmentDoc = await _firestore
            .collection('appointments')
            .doc(bookedSlots.first['appointmentId'])
            .get();
        if (appointmentDoc.exists) {
          final appointmentData = appointmentDoc.data() as Map<String, dynamic>;
          _currentDoctorId = appointmentData['doctorId'];
        }
      }

      // Option 3: Default doctor ID if none found (adjust as needed)
      _currentDoctorId ??= 'default_doctor_id';
    } catch (e) {
      debugPrint('Error getting current doctor ID: $e');
    }
  }

  // NEW: Listen to doctor session changes to update scheduler estimates
  void _startDoctorSessionListener() {
    if (_isDisposed || !_schedulerInitialized) return;

    _doctorSessionSubscription?.cancel();
    _doctorSessionSubscription = _firestore
        .collection('doctor_sessions')
        .doc('current')
        .snapshots()
        .listen((snapshot) {
      if (_isDisposed) return;

      if (snapshot.exists) {
        final data = snapshot.data() as Map<String, dynamic>;
        final isActive = data['isActive'] ?? false;
        final isPaused = data['isPaused'] ?? false;

        // When doctor session changes, refresh scheduler estimates
        if (isActive && !isPaused) {
          _refreshSchedulerEstimates();
        }
      }
    });
  }

  // NEW: Timer to periodically refresh scheduler estimates
  void _startSchedulerRefreshTimer() {
    if (_isDisposed || !_schedulerInitialized) return;

    _schedulerRefreshTimer?.cancel();
    _schedulerRefreshTimer =
        Timer.periodic(const Duration(seconds: 45), (timer) {
      if (!_isDisposed) {
        _refreshSchedulerEstimates();
      }
    });
  }

  // NEW: Refresh scheduler estimates for all valid appointments
  Future<void> _refreshSchedulerEstimates() async {
    if (_isDisposed || !_schedulerInitialized) return;

    try {
      for (var slot in validSlots) {
        final appointmentId = slot['appointmentId'];
        await _getSchedulerEstimate(appointmentId);
      }
    } catch (e) {
      debugPrint('Error refreshing scheduler estimates: $e');
    }
  }

  // NEW: Get scheduler estimate for a specific appointment
  Future<Map<String, dynamic>?> _getSchedulerEstimate(
      String appointmentId) async {
    if (_isDisposed || !_schedulerInitialized) return null;

    try {
      // Check cache first
      if (_schedulerEstimates.containsKey(appointmentId) &&
          _estimatesFetchTimes.containsKey(appointmentId)) {
        final lastFetch = _estimatesFetchTimes[appointmentId]!;
        if (DateTime.now().difference(lastFetch) < _cacheDuration) {
          return _schedulerEstimates[appointmentId];
        }
      }

      // Get fresh estimate from scheduler
      final estimate = _scheduler.getPatientStatus(appointmentId);

      if (!_isDisposed && estimate['status'] == 'success') {
        _schedulerEstimates[appointmentId] = estimate;
        _estimatesFetchTimes[appointmentId] = DateTime.now();
        notifyListeners();
        return estimate;
      }

      return estimate;
    } catch (e) {
      debugPrint('Error getting scheduler estimate for $appointmentId: $e');
      return null;
    }
  }

  // ENHANCED: Get patient status with scheduler integration
  Future<Map<String, dynamic>> getPatientStatus(String appointmentId) async {
    if (_isDisposed) {
      throw Exception('ViewModel is disposed');
    }

    try {
      // Check cache first
      if (_cachedStatuses.containsKey(appointmentId) &&
          _lastFetchTimes.containsKey(appointmentId)) {
        final lastFetch = _lastFetchTimes[appointmentId]!;
        if (DateTime.now().difference(lastFetch) < _cacheDuration) {
          return _cachedStatuses[appointmentId]!;
        }
      }

      // Get both scheduler estimate and basic status
      Map<String, dynamic>? schedulerEstimate;
      if (_schedulerInitialized) {
        schedulerEstimate = await _getSchedulerEstimate(appointmentId);
      }

      // Get basic status from scheduler
      final status = _scheduler.getPatientStatus(appointmentId);

      // Fallback: read from patient_queue (mirrored by doctor VM)
      try {
        final now = DateTime.now();
        final dateStr = DateFormat('yyyy-MM-dd').format(now);
        final pqId = '${dateStr}_$appointmentId';
        debugPrint('[TicketViewModel] Looking for patient_queue doc: $pqId');
        final pqDoc =
            await _firestore.collection('patient_queue').doc(pqId).get();
        if (pqDoc.exists) {
          final pq = pqDoc.data() as Map<String, dynamic>;
          debugPrint('[TicketViewModel] Found patient_queue data: $pq');
          if (status['data'] == null) status['data'] = <String, dynamic>{};
          final data = status['data'] as Map<String, dynamic>;
          data['queuePosition'] = pq['queuePosition'] ?? data['queuePosition'];
          data['waitingTimeMinutes'] =
              pq['estimatedWaitTime'] ?? data['waitingTimeMinutes'];
          data['estimatedCallTime'] = data['estimatedCallTime'];
          data['currentStatus'] = pq['status'] ?? data['currentStatus'];
          data['isFromPatientQueue'] = true;
          data['lastUpdatedFromPatientQueue'] =
              pq['lastUpdated']?.toString() ?? DateTime.now().toIso8601String();
          debugPrint(
              '[TicketViewModel] Updated status with patient_queue: queuePosition=${data['queuePosition']}, waitingTimeMinutes=${data['waitingTimeMinutes']}');
        } else {
          debugPrint('[TicketViewModel] No patient_queue doc found for: $pqId');
        }
      } catch (e) {
        debugPrint('patient_queue fallback error: $e');
      }

      // Merge scheduler estimate with basic status
      Map<String, dynamic> enhancedStatus = Map.from(status);

      if (schedulerEstimate != null &&
          schedulerEstimate['status'] == 'success') {
        final schedulerData =
            schedulerEstimate['data'] as Map<String, dynamic>?;
        if (schedulerData != null) {
          // Merge scheduler data with existing status data
          if (enhancedStatus['data'] == null) {
            enhancedStatus['data'] = <String, dynamic>{};
          }

          final statusData = enhancedStatus['data'] as Map<String, dynamic>;

          // Add scheduler-specific data
          statusData['queuePosition'] = schedulerData['queuePosition'];
          statusData['waitingTimeMinutes'] =
              schedulerData['waitingTimeMinutes'];
          statusData['estimatedCallTime'] = schedulerData['estimatedCallTime'];
          statusData['consultationStatus'] =
              schedulerData['currentStatus'] ?? statusData['currentStatus'];
          statusData['consultationStartTime'] =
              schedulerData['startTime'] ?? statusData['consultationStartTime'];
          // Use scheduler's more accurate waiting time if available
          if (schedulerData['waitingTimeMinutes'] != null) {
            statusData['accurateWaitingTime'] =
                '${schedulerData['waitingTimeMinutes']} minutes';
          }
          // Add additional scheduler insights
          statusData['isFromScheduler'] = true;
          statusData['lastUpdatedFromScheduler'] =
              DateTime.now().toIso8601String();
        }
      }
      // --- NEW: fetch doctor stats when getting status ---
      await fetchDoctorStats();

      if (!_isDisposed) {
        _cachedStatuses[appointmentId] = enhancedStatus;
        _lastFetchTimes[appointmentId] = DateTime.now();
        _retryCounts[appointmentId] = 0;
        _errorMessage = null;
        // Don't call notifyListeners here - it causes flickering
        // Only notify when there's a significant change (handled by listeners)
      }

      return enhancedStatus;
    } catch (e) {
      if (e is FirebaseException && e.code == 'too-many-attempts') {
        final currentRetries = _retryCounts[appointmentId] ?? 0;

        if (currentRetries < _maxRetries && !_isDisposed) {
          _retryCounts[appointmentId] = currentRetries + 1;
          await Future.delayed(
              Duration(seconds: pow(2, currentRetries + 1).toInt()));
          return getPatientStatus(appointmentId);
        }

        // Return cached data if available
        if (_cachedStatuses.containsKey(appointmentId)) {
          return _cachedStatuses[appointmentId]!;
        }

        _errorMessage =
            'Unable to fetch status after $_maxRetries attempts. Please try again later.';
        notifyListeners();
        throw Exception(_errorMessage);
      }

      _errorMessage = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  // ENHANCED: Update waiting times with scheduler integration
  void _updateWaitingTimes() {
    if (_isDisposed) return;

    if (!_isDoctorSeeing) {
      waitingTime = "Doctor hasn't started seeing patients";
      if (!_isDisposed) notifyListeners();
      return;
    }

    final validAppointments = validSlots;

    if (validAppointments.isEmpty) {
      waitingTime = "No pending appointments";
      if (!_isDisposed) notifyListeners();
      return;
    }

    final nextAppointment = validAppointments.first;
    final appointmentId = nextAppointment['appointmentId'];

    // Try to get scheduler estimate first
    if (_schedulerInitialized &&
        _schedulerEstimates.containsKey(appointmentId)) {
      final schedulerData =
          _schedulerEstimates[appointmentId]?['data'] as Map<String, dynamic>?;

      if (schedulerData != null &&
          schedulerData['waitingTimeMinutes'] != null) {
        final waitingMinutes = schedulerData['waitingTimeMinutes'] as int;
        final queuePosition = schedulerData['queuePosition'] as int?;

        String estimatedTime;
        if (waitingMinutes > 60) {
          final hours = (waitingMinutes / 60).floor();
          final minutes = waitingMinutes % 60;
          estimatedTime = '${hours}h ${minutes}m';
        } else {
          estimatedTime = '${waitingMinutes}m';
        }

        if (queuePosition != null) {
          waitingTime = 'Position: $queuePosition | Wait: $estimatedTime';
        } else {
          waitingTime = 'Estimated wait: $estimatedTime';
        }

        if (!_isDisposed) notifyListeners();
        return;
      }
    }

    // Fallback to original calculation if scheduler data not available
    final estimatedTime =
        _calculateEstimatedTime(nextAppointment['slotNumber'] as int);
    waitingTime = 'Estimated wait: $estimatedTime';

    if (!_isDisposed) notifyListeners();
  }

  // Modified helper method to check if appointment is current or next day with pending status
  bool _isValidAppointment(Map<String, dynamic> slot) {
    try {
      // Only show pending appointments
      if (slot['status'] != 'pending') {
        return false;
      }

      // Use correct date format (yyyy-MM-dd)
      final dateFormat = DateFormat('yyyy-MM-dd');
      final appointmentDate = dateFormat.parse(slot['date']);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final tomorrow = today.add(const Duration(days: 1));

      // Check if appointment is today or tomorrow
      final appointmentDateOnly = DateTime(
          appointmentDate.year, appointmentDate.month, appointmentDate.day);

      return appointmentDateOnly == today || appointmentDateOnly == tomorrow;
    } catch (e) {
      debugPrint('Error parsing date: $e');
      return false;
    }
  }

  // Get valid appointments (current and next day with pending status only)
  List<Map<String, dynamic>> get validSlots =>
      bookedSlots.where(_isValidAppointment).toList();

  // Refresh timer to invalidate cache
  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(_cacheDuration, (timer) {
      if (!_isDisposed) {
        // Clear cache to force refresh
        _lastFetchTimes.clear();
        _estimatesFetchTimes
            .clear(); // NEW: Also clear scheduler estimates cache
        notifyListeners();
      }
    });
  }

  void _startSessionListener() {
    if (_isDisposed) return;

    _sessionSubscription?.cancel();
    _sessionSubscription = _firestore
        .collection('doctor_sessions')
        .doc('current')
        .snapshots()
        .listen((snapshot) {
      if (_isDisposed) return;

      if (snapshot.exists) {
        final data = snapshot.data() as Map<String, dynamic>;
        final isActive = data['isActive'] ?? false;
        final isPaused = data['isPaused'] ?? false;
        final doctorStarted = data['doctorStartedSeeing'] ?? false;

        // Update doctor status based on session state
        if (!isActive) {
          _doctorStatus = 'Doctor not present currently';
          waitingTime = 'Doctor has not started the session';
        } else if (isPaused) {
          _doctorStatus = 'Doctor on break';
          waitingTime = 'Doctor is currently on break';
        } else if (isActive && doctorStarted) {
          _doctorStatus = 'Doctor is seeing patients';
          _isDoctorSeeing = true;
          _updateWaitingTimes(); // This will calculate actual waiting times
        }

        _sessionStartTime = (data['startTime'] as Timestamp?)?.toDate();

        // Clear timer if doctor is not active or is on break
        if (!isActive || isPaused) {
          _timer?.cancel();
        } else if (isActive && !isPaused) {
          _startTimer();
        }

        if (!_isDisposed) notifyListeners();
      } else {
        // No session document exists
        _doctorStatus = 'Doctor not present currently';
        waitingTime = 'No active session';
        _isDoctorSeeing = false;
        _timer?.cancel();
        if (!_isDisposed) notifyListeners();
      }
    }, onError: (error) {
      debugPrint('Error in session listener: $error');
      if (!_isDisposed) {
        _doctorStatus = 'Unable to get doctor status';
        waitingTime = 'Error getting status';
        notifyListeners();
      }
    });
  }

  void _startAppointmentsListener() {
    if (_isDisposed) return;

    debugPrint('Starting appointments listener for userId: $userId');

    // Get today and tomorrow dates for filtering
    final now = DateTime.now();
    final today = DateFormat('yyyy-MM-dd').format(now);
    final tomorrow =
        DateFormat('yyyy-MM-dd').format(now.add(const Duration(days: 1)));

    debugPrint('Fetching appointments for dates: $today and $tomorrow');

    _appointmentsSubscription?.cancel();
    _appointmentsSubscription = _firestore
        .collection('appointments')
        .where('patientId', isEqualTo: userId)
        .where('status',
            isEqualTo: 'pending') // Only fetch pending appointments
        .where('appointmentDate',
            whereIn: [today, tomorrow]) // Only current and next day
        .snapshots()
        .listen((snapshot) {
          if (_isDisposed) return;

          debugPrint(
              'Received ${snapshot.docs.length} pending appointments from Firestore');

          try {
            bookedSlots = snapshot.docs.map((doc) {
              final data = doc.data();
              debugPrint('Processing appointment: ${doc.id}, data: $data');

              return {
                'slotNumber': data['seatNumber'],
                'date': data['appointmentDate'],
                'time': data['appointmentTime'],
                'status': data['status'],
                'appointmentId': doc.id,
              };
            }).toList();

            debugPrint('Total booked slots: ${bookedSlots.length}');

            // Sort slots by date and time using proper date parsing
            bookedSlots.sort((a, b) {
              try {
                final dateTimeA = _parseAppointmentDateTime(
                    a['date'].toString(),
                    a['time'].toString().split('-')[0].trim());
                final dateTimeB = _parseAppointmentDateTime(
                    b['date'].toString(),
                    b['time'].toString().split('-')[0].trim());

                return dateTimeA.compareTo(dateTimeB);
              } catch (e) {
                debugPrint('Error comparing dates/times: $e');
                return 0;
              }
            });

            debugPrint('Valid slots after filtering: ${validSlots.length}');

            // Debounce updates to prevent flickering
            _debounceTimer?.cancel();
            _debounceTimer = Timer(const Duration(milliseconds: 300), () {
              if (_isDisposed) return;

              _updateWaitingTimes();

              // NEW: Refresh scheduler estimates when appointments change
              if (_schedulerInitialized) {
                _refreshSchedulerEstimates();
              }

              // --- NEW: Start real-time listeners for appointment status ---
              startAppointmentStatusListeners();

              // --- NEW: Start queue update listener ---
              _startQueueUpdateListener();

              // --- NEW: Fetch doctor stats for "patients seen today" ---
              fetchDoctorStats(); // Don't await to avoid blocking

              if (!_isDisposed) notifyListeners();
            });
          } catch (e) {
            debugPrint('Error processing appointments: $e');
            _errorMessage = 'Error processing appointments: $e';
            notifyListeners();
          }
        }, onError: (error) {
          debugPrint('Firestore listener error: $error');
          _errorMessage = 'Database connection error: $error';
          notifyListeners();
        });
  }

  void _startTimer() {
    if (_isDisposed) return;

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isDisposed) {
        _updateWaitingTimes();
      }
    });
  }

  Future<void> _loadPatientData() async {
    if (_isDisposed) return;

    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();

      if (!userDoc.exists) return;

      final userData = userDoc.data() as Map<String, dynamic>;
      patientName = userData['patientName'] ?? userData['name'] ?? 'Unknown';
      doctorName = userData['doctorName'] ?? 'Dr. Rajneesh Chaudhary';

      averageConsultationTime = _scheduler.getAverageConsultationTime();
      _updateWaitingTimes();

      if (!_isDisposed) notifyListeners();
    } catch (e) {
      debugPrint('Error loading patient data: $e');
      _errorMessage = 'Error loading patient data: $e';
      notifyListeners();
    }
  }

  String _calculateEstimatedTime(int slotNumber) {
    if (averageConsultationTime <= 0) return "Calculating...";

    final estimatedMinutes = (slotNumber - 1) * averageConsultationTime;
    final hours = (estimatedMinutes / 60).floor();
    final minutes = (estimatedMinutes % 60).round();

    if (hours > 0) {
      return '$hours hour${hours > 1 ? 's' : ''} $minutes min';
    }
    return '$minutes minutes';
  }

  void toggleExpand() {
    if (_isDisposed) return;
    isExpanded = !isExpanded;
    notifyListeners();
  }

  Future<void> loadBookedSlots() async {
    if (_isDisposed) return;

    debugPrint('Loading booked slots for userId: $userId');

    isLoading = true;
    notifyListeners();

    try {
      // Get today and tomorrow dates for filtering
      final now = DateTime.now();
      final today = DateFormat('yyyy-MM-dd').format(now);
      final tomorrow =
          DateFormat('yyyy-MM-dd').format(now.add(const Duration(days: 1)));

      // NEW: Fetch doctor stats for "patients seen today"
      await fetchDoctorStats();

      final snapshot = await _firestore
          .collection('appointments')
          .where('patientId', isEqualTo: userId)
          .where('status',
              isEqualTo: 'pending') // Only fetch pending appointments
          .where('appointmentDate',
              whereIn: [today, tomorrow]) // Only current and next day
          .get();

      debugPrint(
          'Found ${snapshot.docs.length} pending appointments in database for today and tomorrow');

      bookedSlots = snapshot.docs.map((doc) {
        final data = doc.data();
        debugPrint('Appointment data: $data');

        return {
          'slotNumber': data['seatNumber'],
          'date': data['appointmentDate'],
          'time': data['appointmentTime'],
          'status': data['status'],
          'appointmentId': doc.id,
        };
      }).toList();

      // Sort slots by date and time
      bookedSlots.sort((a, b) {
        final dateTimeA = _parseAppointmentDateTime(
            a['date'].toString(), a['time'].toString().split('-')[0].trim());
        final dateTimeB = _parseAppointmentDateTime(
            b['date'].toString(), b['time'].toString().split('-')[0].trim());
        return dateTimeA.compareTo(dateTimeB);
      });

      debugPrint('Total booked slots: ${bookedSlots.length}');
      debugPrint('Valid slots: ${validSlots.length}');

      _updateWaitingTimes();

      // NEW: Refresh scheduler estimates after loading slots
      if (_schedulerInitialized) {
        _refreshSchedulerEstimates();
      }
    } catch (e) {
      debugPrint('Error loading booked slots: $e');
      _errorMessage = 'Error loading booked slots: $e';
    } finally {
      isLoading = false;
      if (!_isDisposed) notifyListeners();
    }
  }

  Future<void> cancelAppointment(String appointmentId) async {
    try {
      // Clear cache for this appointment
      _cachedStatuses.remove(appointmentId);
      _lastFetchTimes.remove(appointmentId);
      _retryCounts.remove(appointmentId);
      _schedulerEstimates.remove(appointmentId); // NEW: Clear scheduler cache
      _estimatesFetchTimes
          .remove(appointmentId); // NEW: Clear scheduler fetch times

      // Add your appointment cancellation logic here
      // Example: await _api.cancelAppointment(appointmentId);
      await loadBookedSlots(); // Refresh the slots after cancellation
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Error cancelling appointment: $e';
      notifyListeners();
      rethrow; // Propagate error to UI for handling
    }
  }

  // Retry mechanism for failed status fetches
  void retryStatusFetch(String appointmentId) {
    _retryCounts[appointmentId] = 0;
    _cachedStatuses.remove(appointmentId);
    _lastFetchTimes.remove(appointmentId);
    _schedulerEstimates.remove(appointmentId); // NEW: Clear scheduler cache
    _estimatesFetchTimes
        .remove(appointmentId); // NEW: Clear scheduler fetch times
    _errorMessage = null;
    notifyListeners();
  }

  // Clear all caches and errors
  void clearCache() {
    _cachedStatuses.clear();
    _lastFetchTimes.clear();
    _retryCounts.clear();
    _schedulerEstimates.clear(); // NEW: Clear scheduler cache
    _estimatesFetchTimes.clear(); // NEW: Clear scheduler fetch times
    _errorMessage = null;
    notifyListeners();
  }

  // NEW: Get scheduler-enhanced waiting time for a specific appointment
  String getEnhancedWaitingTime(String appointmentId) {
    final slot = bookedSlots.firstWhere(
      (s) => s['appointmentId'] == appointmentId,
      orElse: () => {},
    );

    if (slot.isEmpty) return "Not found";

    final int? slotNumber = slot['slotNumber'] as int?;
    if (slotNumber == null) return "Invalid slot";

    // FIRST: Try to get data from patient_queue (most accurate, updated by doctor)
    try {
      // Use synchronous approach for this method
      // We'll check if we have cached data from getPatientStatus
      if (_cachedStatuses.containsKey(appointmentId)) {
        final cached = _cachedStatuses[appointmentId]!;
        final data = cached['data'] as Map<String, dynamic>?;
        if (data != null && data['isFromPatientQueue'] == true) {
          final queuePos = data['queuePosition'] as int?;
          final waitingMin = data['waitingTimeMinutes'] as num?;
          if (queuePos != null && waitingMin != null) {
            final patientsAhead = queuePos - 1;
            final hours = waitingMin.toInt() ~/ 60;
            final mins = waitingMin.toInt() % 60;
            final waitStr =
                hours > 0 ? '${hours}h ${mins}m' : '${waitingMin.toInt()}m';
            return 'Wait: $waitStr • Ahead: ${patientsAhead < 0 ? 0 : patientsAhead}';
          }
        }
      }
    } catch (e) {
      debugPrint('[getEnhancedWaitingTime] Error reading patient_queue: $e');
    }

    // SECOND: Prefer scheduler estimate if available
    if (_schedulerInitialized) {
      final estimate = _schedulerEstimates[appointmentId]?['data'];
      final waitingMin = estimate?['waitingTimeMinutes'] as int?;
      final queuePos = estimate?['queuePosition'] as int?;
      if (waitingMin != null) {
        final patientsAhead = (queuePos ?? slotNumber) - 1;
        final hours = waitingMin ~/ 60;
        final mins = waitingMin % 60;
        final waitStr = hours > 0 ? '${hours}h ${mins}m' : '${waitingMin}m';
        return 'Wait: $waitStr • Ahead: ${patientsAhead < 0 ? 0 : patientsAhead}';
      }
    }

    // THIRD: Fallback: average + std deviation buffer
    final avg = _scheduler.averageConsultationTime; // minutes
    final patientsAhead = slotNumber - (_scheduler.currentPatientNumber ?? 0);
    if (patientsAhead <= 0) return "You're next!";

    // One stddev as buffer to be conservative
    final bufferPerPatient = max(0, _scheduler.standardDeviation.round());
    final estMinutes =
        (patientsAhead * avg).round() + (patientsAhead * bufferPerPatient);
    final hours = estMinutes ~/ 60;
    final mins = estMinutes % 60;
    final waitStr = hours > 0 ? '${hours}h ${mins}m' : '${estMinutes}m';

    return 'Wait: $waitStr • Ahead: $patientsAhead';
  }

  // NEW: Start queue update listener with debouncing
  void _startQueueUpdateListener() {
    if (_isDisposed) return;

    _queueUpdateSubscription?.cancel();
    _queueUpdateSubscription = _firestore
        .collection('queue_updates')
        .doc('latest')
        .snapshots()
        .listen((snapshot) {
      if (_isDisposed) return;

      if (snapshot.exists) {
        final data = snapshot.data() as Map<String, dynamic>;
        debugPrint('[TicketViewModel] Queue update received: $data');

        // Debounce updates to prevent flickering (wait 500ms before updating)
        _debounceTimer?.cancel();
        _debounceTimer = Timer(const Duration(milliseconds: 500), () {
          if (_isDisposed) return;

          // Clear cache to force refresh of patient status
          clearCache();

          // Update waiting times
          _updateWaitingTimes();

          // Refresh doctor stats (patients seen today)
          fetchDoctorStats(); // Don't await to avoid blocking

          if (!_isDisposed) notifyListeners();
        });
      }
    }, onError: (error) {
      debugPrint('[TicketViewModel] Queue update listener error: $error');
    });
  }

  // Getters for error state
  String? get errorMessage => _errorMessage;
  bool get hasError => _errorMessage != null;
  bool get isSchedulerIntegrated => _schedulerInitialized;

  // Add these getters for UI access
  String get doctorStatus => _doctorStatus;
  bool get isDoctorSeeing => _isDoctorSeeing;
  DateTime? get sessionStartTime => _sessionStartTime;

  @override
  void dispose() {
    _isDisposed = true;
    _timer?.cancel();
    _refreshTimer?.cancel();
    _schedulerRefreshTimer?.cancel(); // NEW: Cancel scheduler refresh timer
    _debounceTimer?.cancel(); // NEW: Cancel debounce timer
    _sessionSubscription?.cancel();
    _appointmentsSubscription?.cancel();
    _doctorSessionSubscription
        ?.cancel(); // NEW: Cancel doctor session subscription
    _queueUpdateSubscription?.cancel(); // NEW: Cancel queue update subscription
    stopAppointmentStatusListeners(); // NEW: Cancel real-time appointment listeners
    super.dispose();
  }

  // Helper method to parse appointment datetime
  DateTime _parseAppointmentDateTime(String date, String time) {
    // Parse the date which is in yyyy-MM-dd format
    final DateTime appointmentDate = DateFormat('yyyy-MM-dd').parse(date);

    // Parse the time which is in h:mm a format (e.g. "9:15 AM")
    final DateTime timeOnly = DateFormat('h:mm a').parse(time);

    // Combine date and time
    return DateTime(
      appointmentDate.year,
      appointmentDate.month,
      appointmentDate.day,
      timeOnly.hour,
      timeOnly.minute,
    );
  }

  // Fetch doctor's stats (completed consultations today)
  Future<void> fetchDoctorStats() async {
    if (_currentDoctorId == null) return;
    try {
      final statsDoc = await _firestore
          .collection('doctor_stats')
          .doc(_currentDoctorId)
          .get();
      if (statsDoc.exists) {
        final data = statsDoc.data() as Map<String, dynamic>;
        completedConsultationsToday =
            data['completedConsultationsToday']?.toInt() ?? 0;
        todayDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error fetching doctor stats: $e');
    }
  }

  void startAppointmentStatusListeners() {
    // Cancel any existing listeners
    for (final sub in _appointmentStatusSubscriptions.values) {
      sub.cancel();
    }
    _appointmentStatusSubscriptions.clear();
    // Listen to all valid appointments
    for (final slot in validSlots) {
      final appointmentId = slot['appointmentId'];
      final sub = _firestore
          .collection('appointments')
          .doc(appointmentId)
          .snapshots()
          .listen((snapshot) async {
        if (!snapshot.exists) return;
        // When the appointment changes, fetch the new status and update cache
        await getPatientStatus(appointmentId);
      });
      _appointmentStatusSubscriptions[appointmentId] = sub;
    }
  }

  void stopAppointmentStatusListeners() {
    for (final sub in _appointmentStatusSubscriptions.values) {
      sub.cancel();
    }
    _appointmentStatusSubscriptions.clear();
  }
}
