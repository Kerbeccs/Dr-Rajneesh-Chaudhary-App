import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class Patient {
  final String id;
  final DateTime arrivalTime;
  Duration? consultationTime;
  DateTime? startTime;
  DateTime? endTime;
  String name;
  String phone;
  String? appointmentId; // Added to track database appointment

  Patient(this.id, this.arrivalTime,
      {this.name = '', this.phone = '', this.appointmentId});

  // Factory constructor to create Patient from Firestore document
  factory Patient.fromFirestore(Map<String, dynamic> data, String docId) {
    return Patient(
      data['patientId'] ?? docId,
      (data['appointmentTime'] as Timestamp).toDate(),
      name: data['patientName'] ?? '',
      phone: data['patientPhone'] ?? '',
      appointmentId: docId,
    );
  }
}

class DoctorScheduler {
  final List<Patient> patients = [];
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  double averageConsultationTime = 10.0;
  double standardDeviation = 0.0;
  int totalPatientsSeen = 0;

  // Doctor status
  bool isDoctorOnBreak = false;
  DateTime? breakStartTime;
  Duration totalBreakTime = Duration.zero;

  // Currently active patient
  Patient? currentPatient;

  bool _isDisposed = false;
  bool _isLoading = false;

  // Getters
  double getAverageConsultationTime() {
    if (_isDisposed) throw Exception('Scheduler is disposed');
    return averageConsultationTime;
  }

  bool get isLoading => _isLoading;

  // NEW: Load patients from database for current date
  Future<Map<String, dynamic>> loadTodaysAppointments(String doctorId) async {
    if (_isDisposed) throw Exception('Scheduler is disposed');

    try {
      _isLoading = true;

      // Get start and end of current day
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day, 0, 0, 0);
      final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59);

      debugPrint('Loading appointments for doctor: $doctorId');
      debugPrint(
          'Date range: ${startOfDay.toString()} to ${endOfDay.toString()}');

      final snapshot = await _firestore
          .collection('bookings')
          .where('doctorId', isEqualTo: doctorId)
          .where('appointmentTime',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('appointmentTime',
              isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
          .orderBy('appointmentTime', descending: false)
          .get();

      // Clear existing patients and load from database
      patients.clear();

      for (var doc in snapshot.docs) {
        try {
          final data = doc.data();
          final patient = Patient.fromFirestore(data, doc.id);

          // Check if patient status exists in database and apply it
          if (data.containsKey('consultationStatus')) {
            switch (data['consultationStatus']) {
              case 'completed':
                patient.startTime = data['consultationStartTime'] != null
                    ? (data['consultationStartTime'] as Timestamp).toDate()
                    : null;
                patient.endTime = data['consultationEndTime'] != null
                    ? (data['consultationEndTime'] as Timestamp).toDate()
                    : null;
                if (data['consultationDurationMinutes'] != null) {
                  patient.consultationTime =
                      Duration(minutes: data['consultationDurationMinutes']);
                }
                break;
              case 'in_consultation':
                patient.startTime = data['consultationStartTime'] != null
                    ? (data['consultationStartTime'] as Timestamp).toDate()
                    : null;
                currentPatient = patient;
                break;
              case 'waiting':
              default:
                // Patient is waiting - no additional setup needed
                break;
            }
          }

          patients.add(patient);
          debugPrint(
              'Added patient: ${patient.name} at ${patient.arrivalTime}');
        } catch (e) {
          debugPrint('Error processing patient ${doc.id}: $e');
          continue;
        }
      }

      // Update statistics based on completed patients
      _updateStatisticsFromDatabase();

      _isLoading = false;

      return {
        'status': 'success',
        'message': 'Loaded ${patients.length} appointments for today',
        'data': {
          'appointmentsLoaded': patients.length,
          'waiting': patients
              .where((p) => p.startTime == null && p.endTime == null)
              .length,
          'inConsultation': patients
              .where((p) => p.startTime != null && p.endTime == null)
              .length,
          'completed': patients.where((p) => p.endTime != null).length,
          'currentPatient': currentPatient?.name,
          'loadTime': DateTime.now().toString()
        }
      };
    } catch (e) {
      _isLoading = false;
      debugPrint('Error loading appointments: $e');
      return {
        'status': 'error',
        'message': 'Failed to load appointments: $e',
        'data': null
      };
    }
  }

  // NEW: Update statistics from database data
  void _updateStatisticsFromDatabase() {
    final completedPatients =
        patients.where((p) => p.consultationTime != null).toList();

    if (completedPatients.isNotEmpty) {
      totalPatientsSeen = completedPatients.length;

      // Recalculate average consultation time
      double totalMinutes = completedPatients
          .map((p) => p.consultationTime!.inMinutes.toDouble())
          .reduce((a, b) => a + b);

      averageConsultationTime = totalMinutes / totalPatientsSeen;

      // Recalculate standard deviation
      if (totalPatientsSeen > 1) {
        double variance = completedPatients
                .map((p) => pow(
                    p.consultationTime!.inMinutes - averageConsultationTime, 2))
                .reduce((a, b) => a + b) /
            totalPatientsSeen;
        standardDeviation = sqrt(variance);
      }
    }
  }

  // MODIFIED: Enhanced add multiple patients method
  void addMultiplePatients(List<Map<String, String>> patientData) {
    if (_isDisposed) return;
    for (var data in patientData) {
      try {
        final timeString = data['arrivalTime'] ?? '';
        final timeFormat = DateFormat('h:mm a');
        final time = timeFormat.parse(timeString);

        final now = DateTime.now();
        final arrivalTime = DateTime(
          now.year,
          now.month,
          now.day,
          time.hour,
          time.minute,
        );

        final patient = Patient(
          data['id'] ?? '',
          arrivalTime,
          name: data['name'] ?? '',
          phone: data['phone'] ?? '',
        );
        patients.add(patient);
      } catch (e) {
        debugPrint('Error parsing time for patient ${data['id']}: $e');
        continue;
      }
    }
  }

  // MODIFIED: Enhanced start consultation with database update
  Future<Map<String, dynamic>> startConsultation(String patientId) async {
    if (_isDisposed) throw Exception('Scheduler is disposed');
    if (isDoctorOnBreak) {
      return {
        'status': 'error',
        'message': 'Cannot start consultation while doctor is on break',
        'data': null
      };
    }

    Patient? patient = getPatientById(patientId);
    if (patient == null) {
      return {'status': 'error', 'message': 'Invalid patient ID', 'data': null};
    }

    if (patient.startTime != null) {
      return {
        'status': 'error',
        'message': 'Patient ${patient.name} is already in consultation',
        'data': null
      };
    }

    if (patient.endTime != null) {
      return {
        'status': 'error',
        'message': 'Patient ${patient.name} has already completed consultation',
        'data': null
      };
    }

    if (currentPatient != null && currentPatient!.endTime == null) {
      return {
        'status': 'error',
        'message':
            'Another patient (${currentPatient!.name}) is currently in consultation',
        'data': {'currentPatientId': currentPatient!.id}
      };
    }

    patient.startTime = DateTime.now();
    currentPatient = patient;

    // Update database
    if (patient.appointmentId != null) {
      try {
        await _firestore
            .collection('bookings')
            .doc(patient.appointmentId)
            .update({
          'consultationStatus': 'in_consultation',
          'consultationStartTime': Timestamp.fromDate(patient.startTime!),
          'lastUpdated': Timestamp.now(),
        });
      } catch (e) {
        debugPrint('Error updating database for start consultation: $e');
        // Continue even if database update fails
      }
    }

    return {
      'status': 'success',
      'message': 'Consultation started for ${patient.name}',
      'data': {
        'patientId': patient.id,
        'patientName': patient.name,
        'startTime': patient.startTime.toString(),
        'estimatedDuration': averageConsultationTime.round()
      }
    };
  }

  // MODIFIED: Enhanced mark as completed with database update
  Future<Map<String, dynamic>> markAsCompleted(
      String patientId, int actualMinutes) async {
    if (_isDisposed) throw Exception('Scheduler is disposed');
    if (isDoctorOnBreak) {
      return {
        'status': 'error',
        'message': 'Cannot complete consultation while doctor is on break',
        'data': null
      };
    }

    Patient? patient = getPatientById(patientId);
    if (patient == null) {
      return {'status': 'error', 'message': 'Invalid patient ID', 'data': null};
    }

    if (patient.startTime == null) {
      return {
        'status': 'error',
        'message': 'Patient ${patient.name} hasn\'t started consultation yet',
        'data': null
      };
    }

    if (patient.endTime != null) {
      return {
        'status': 'error',
        'message':
            'Patient ${patient.name} has already been marked as completed',
        'data': null
      };
    }

    double oldAverage = averageConsultationTime;

    // Mark as completed
    patient.endTime = DateTime.now();
    patient.consultationTime = Duration(minutes: actualMinutes);
    totalPatientsSeen++;

    // Clear current patient if this was the active one
    if (currentPatient == patient) {
      currentPatient = null;
    }

    // Update rolling average
    double newAverage =
        (averageConsultationTime * (totalPatientsSeen - 1) + actualMinutes) /
            totalPatientsSeen;

    // Update standard deviation
    if (totalPatientsSeen > 1) {
      double prevVariance = pow(standardDeviation, 2).toDouble();
      double newVariance = ((totalPatientsSeen - 1) * prevVariance +
              pow(actualMinutes - newAverage, 2)) /
          totalPatientsSeen;
      standardDeviation = sqrt(newVariance);
    }

    averageConsultationTime = newAverage;

    // Update database
    if (patient.appointmentId != null) {
      try {
        await _firestore
            .collection('bookings')
            .doc(patient.appointmentId)
            .update({
          'consultationStatus': 'completed',
          'consultationEndTime': Timestamp.fromDate(patient.endTime!),
          'consultationDurationMinutes': actualMinutes,
          'lastUpdated': Timestamp.now(),
        });
      } catch (e) {
        debugPrint('Error updating database for completion: $e');
        // Continue even if database update fails
      }
    }

    return {
      'status': 'success',
      'message': 'Patient ${patient.name} completed successfully',
      'data': {
        'patientId': patient.id,
        'patientName': patient.name,
        'actualDuration': actualMinutes,
        'oldAverage': oldAverage.toStringAsFixed(1),
        'newAverage': averageConsultationTime.toStringAsFixed(1),
        'totalPatientsSeen': totalPatientsSeen,
        'waitingPatientsUpdated': _getWaitingPatients().length
      }
    };
  }

  // NEW: Refresh appointments from database
  Future<Map<String, dynamic>> refreshAppointments(String doctorId) async {
    return await loadTodaysAppointments(doctorId);
  }

  // NEW: Add walk-in patient (not from database)
  Future<String> addWalkInPatient(String name, String phone) async {
    if (_isDisposed) throw Exception('Scheduler is disposed');

    final patientId = 'walkin_${DateTime.now().millisecondsSinceEpoch}';
    final patient =
        Patient(patientId, DateTime.now(), name: name, phone: phone);
    patients.add(patient);

    // Optionally save walk-in to database
    try {
      await _firestore.collection('bookings').add({
        'patientId': patientId,
        'patientName': name,
        'patientPhone': phone,
        'appointmentTime': Timestamp.fromDate(DateTime.now()),
        'appointmentType': 'walk_in',
        'consultationStatus': 'waiting',
        'createdAt': Timestamp.now(),
      });
    } catch (e) {
      debugPrint('Error saving walk-in patient to database: $e');
      // Continue even if database save fails
    }

    return "Walk-in patient $name added successfully. Current position: ${_getQueuePosition(patient)}";
  }

  // Existing methods remain the same...
  String addPatient(Patient patient) {
    if (_isDisposed) throw Exception('Scheduler is disposed');
    patients.add(patient);
    return "Patient ${patient.name} (ID: ${patient.id}) added to queue";
  }

  String registerNewPatient(String id, String name, String phone) {
    if (_isDisposed) throw Exception('Scheduler is disposed');
    final patient = Patient(id, DateTime.now(), name: name, phone: phone);
    patients.add(patient);
    return "Patient $name registered successfully. Current position: ${_getQueuePosition(patient)}";
  }

  int _getQueuePosition(Patient patient) {
    if (_isDisposed) throw Exception('Scheduler is disposed');
    int position = 1;
    for (Patient p in patients) {
      if (p.arrivalTime.isBefore(patient.arrivalTime) && p.endTime == null) {
        position++;
      }
    }
    return position;
  }

  Map<String, dynamic> pauseDoctor(String reason) {
    if (_isDisposed) throw Exception('Scheduler is disposed');
    if (isDoctorOnBreak) {
      return {
        'status': 'error',
        'message': 'Doctor is already on break',
        'data': null
      };
    }

    isDoctorOnBreak = true;
    breakStartTime = DateTime.now();

    return {
      'status': 'success',
      'message': 'Doctor on break - $reason',
      'data': {
        'breakStartTime': breakStartTime.toString(),
        'affectedPatients': _getWaitingPatients().length
      }
    };
  }

  Map<String, dynamic> resumeDoctor() {
    if (_isDisposed) throw Exception('Scheduler is disposed');
    if (!isDoctorOnBreak) {
      return {
        'status': 'error',
        'message': 'Doctor is not on break',
        'data': null
      };
    }

    Duration breakDuration = Duration.zero;
    if (breakStartTime != null) {
      breakDuration = DateTime.now().difference(breakStartTime!);
      totalBreakTime = totalBreakTime + breakDuration;
    }

    isDoctorOnBreak = false;
    breakStartTime = null;

    return {
      'status': 'success',
      'message': 'Doctor back from break',
      'data': {
        'breakDurationMinutes': breakDuration.inMinutes,
        'totalBreakToday': totalBreakTime.inMinutes,
        'waitingPatients': _getWaitingPatients().length
      }
    };
  }

  Patient? getPatientById(String id) {
    if (_isDisposed) throw Exception('Scheduler is disposed');
    try {
      return patients.firstWhere((p) => p.id == id);
    } catch (e) {
      return null;
    }
  }

  List<Patient> _getWaitingPatients() {
    if (_isDisposed) throw Exception('Scheduler is disposed');
    return patients
        .where((p) => p.startTime == null && p.endTime == null)
        .toList();
  }

  Map<String, dynamic> estimateWaitingTimeById(String patientId) {
    if (_isDisposed) throw Exception('Scheduler is disposed');
    if (isDoctorOnBreak) {
      return {
        'status': 'break',
        'message': 'Doctor is currently on break',
        'data': {
          'patientId': patientId,
          'waitingTime': 'Doctor on break',
          'breakStarted': breakStartTime?.toString()
        }
      };
    }

    Patient? patient = getPatientById(patientId);
    if (patient == null) {
      return {'status': 'error', 'message': 'Invalid patient ID', 'data': null};
    }

    if (patient.endTime != null) {
      return {
        'status': 'completed',
        'message': 'Patient ${patient.name} has completed consultation',
        'data': {
          'patientId': patientId,
          'completedAt': patient.endTime.toString(),
          'duration': patient.consultationTime?.inMinutes
        }
      };
    }

    if (patient.startTime != null) {
      return {
        'status': 'in_consultation',
        'message': 'Patient ${patient.name} is currently in consultation',
        'data': {
          'patientId': patientId,
          'startedAt': patient.startTime.toString(),
          'estimatedCompletion': _getEstimatedCompletionTime(patient)
        }
      };
    }

    int waitingMinutes = _calculateWaitingTime(patient);
    int queuePosition = _getQueuePosition(patient);

    return {
      'status': 'waiting',
      'message': 'Estimated waiting time: $waitingMinutes minutes',
      'data': {
        'patientId': patientId,
        'patientName': patient.name,
        'waitingTimeMinutes': waitingMinutes,
        'queuePosition': queuePosition,
        'patientsAhead': queuePosition - 1,
        'estimatedCallTime':
            DateTime.now().add(Duration(minutes: waitingMinutes)).toString()
      }
    };
  }

  String _getEstimatedCompletionTime(Patient patient) {
    if (_isDisposed) throw Exception('Scheduler is disposed');
    if (patient.startTime == null) return '';

    double elapsedMinutes =
        DateTime.now().difference(patient.startTime!).inMinutes.toDouble();
    double remainingMinutes = max(0, averageConsultationTime - elapsedMinutes);

    return DateTime.now()
        .add(Duration(minutes: remainingMinutes.round()))
        .toString();
  }

  int _calculateWaitingTime(Patient patient) {
    if (_isDisposed) throw Exception('Scheduler is disposed');
    int patientsAhead = 0;
    for (Patient p in patients) {
      if (p.arrivalTime.isBefore(patient.arrivalTime) && p.endTime == null) {
        patientsAhead++;
      }
    }

    DateTime currentTime = DateTime.now();
    double totalMinutes = 0.0;

    if (currentPatient != null && currentPatient!.endTime == null) {
      double elapsedMinutes = currentTime
          .difference(currentPatient!.startTime!)
          .inMinutes
          .toDouble();
      double expectedMinutes = averageConsultationTime;

      if (elapsedMinutes >= expectedMinutes) {
        totalMinutes += 3.0;
      } else {
        totalMinutes += (expectedMinutes - elapsedMinutes);
      }
      patientsAhead--;
    }

    totalMinutes += patientsAhead * averageConsultationTime;
    totalMinutes += (standardDeviation * 0.5);

    return max(1, totalMinutes.round());
  }

  Map<String, dynamic> getPatientStatus(String patientId) {
    if (_isDisposed) throw Exception('Scheduler is disposed');
    Patient? patient = getPatientById(patientId);
    if (patient == null) {
      return {'status': 'error', 'message': 'Invalid patient ID', 'data': null};
    }

    String status;
    Map<String, dynamic> statusData = {
      'id': patient.id,
      'name': patient.name,
      'phone': patient.phone,
      'arrivalTime': patient.arrivalTime.toString(),
    };

    if (patient.endTime != null) {
      status = "Completed";
      statusData.addAll({
        'startTime': patient.startTime?.toString(),
        'endTime': patient.endTime?.toString(),
        'consultationMinutes': patient.consultationTime?.inMinutes,
        'totalTimeInClinic':
            patient.endTime!.difference(patient.arrivalTime).inMinutes
      });
    } else if (patient.startTime != null) {
      status = "In Consultation";
      statusData.addAll({
        'startTime': patient.startTime?.toString(),
        'elapsedMinutes':
            DateTime.now().difference(patient.startTime!).inMinutes,
        'estimatedCompletion': _getEstimatedCompletionTime(patient)
      });
    } else {
      status = "Waiting";
      if (!isDoctorOnBreak) {
        statusData.addAll({
          'waitingTimeMinutes': _calculateWaitingTime(patient),
          'queuePosition': _getQueuePosition(patient),
          'estimatedCallTime': DateTime.now()
              .add(Duration(minutes: _calculateWaitingTime(patient)))
              .toString()
        });
      } else {
        statusData['waitingStatus'] = 'Doctor on break';
      }
    }

    return {
      'status': 'success',
      'message': 'Patient status: $status',
      'data': statusData..['currentStatus'] = status
    };
  }

  Map<String, dynamic> getAllPatients() {
    if (_isDisposed) throw Exception('Scheduler is disposed');
    List<Map<String, dynamic>> patientList = patients.map((p) {
      String status;
      Map<String, dynamic> patientData = {
        'id': p.id,
        'name': p.name,
        'phone': p.phone,
        'arrivalTime': p.arrivalTime.toString(),
        'appointmentId': p.appointmentId,
      };

      if (p.endTime != null) {
        status = "Completed";
        patientData['consultationMinutes'] = p.consultationTime?.inMinutes;
        patientData['completedAt'] = p.endTime.toString();
      } else if (p.startTime != null) {
        status = "In Consultation";
        patientData['startedAt'] = p.startTime.toString();
        patientData['elapsedMinutes'] =
            DateTime.now().difference(p.startTime!).inMinutes;
      } else {
        status = "Waiting";
        if (isDoctorOnBreak) {
          patientData['waitingStatus'] = "Doctor on break";
        } else {
          patientData['waitingTimeMinutes'] = _calculateWaitingTime(p);
          patientData['queuePosition'] = _getQueuePosition(p);
        }
      }

      patientData['status'] = status;
      return patientData;
    }).toList();

    return {
      'status': 'success',
      'message': 'All patients retrieved',
      'data': {
        'patients': patientList,
        'totalPatients': patients.length,
        'waiting': patientList.where((p) => p['status'] == 'Waiting').length,
        'inConsultation':
            patientList.where((p) => p['status'] == 'In Consultation').length,
        'completed':
            patientList.where((p) => p['status'] == 'Completed').length,
      }
    };
  }

  Map<String, dynamic> getStats() {
    if (_isDisposed) throw Exception('Scheduler is disposed');
    final waitingPatients = _getWaitingPatients();
    final completedPatients = patients.where((p) => p.endTime != null).length;
    final inConsultation =
        patients.where((p) => p.startTime != null && p.endTime == null).length;

    return {
      'status': 'success',
      'message': 'System statistics',
      'data': {
        'doctorStatus': isDoctorOnBreak ? 'On Break' : 'Available',
        'isDoctorOnBreak': isDoctorOnBreak,
        'breakStartTime': breakStartTime?.toString(),
        'totalBreakTimeMinutes': totalBreakTime.inMinutes,
        'currentPatient': currentPatient != null
            ? {
                'id': currentPatient!.id,
                'name': currentPatient!.name,
                'startTime': currentPatient!.startTime.toString(),
                'elapsedMinutes': DateTime.now()
                    .difference(currentPatient!.startTime!)
                    .inMinutes
              }
            : null,
        'totalPatients': patients.length,
        'waitingPatients': waitingPatients.length,
        'patientsInConsultation': inConsultation,
        'completedPatients': completedPatients,
        'averageConsultationTime':
            double.parse(averageConsultationTime.toStringAsFixed(2)),
        'standardDeviation': double.parse(standardDeviation.toStringAsFixed(2)),
        'totalPatientsSeen': totalPatientsSeen,
        'nextPatientId':
            waitingPatients.isNotEmpty ? waitingPatients.first.id : null,
        'longestWaitingPatient': _getLongestWaitingPatient(),
        'systemTime': DateTime.now().toString(),
        'clinicStartTime':
            patients.isNotEmpty ? patients.first.arrivalTime.toString() : null,
        'isLoading': _isLoading,
      }
    };
  }

  Map<String, dynamic>? _getLongestWaitingPatient() {
    if (_isDisposed) throw Exception('Scheduler is disposed');
    final waiting = _getWaitingPatients();
    if (waiting.isEmpty) return null;

    Patient longest =
        waiting.reduce((a, b) => a.arrivalTime.isBefore(b.arrivalTime) ? a : b);
    return {
      'id': longest.id,
      'name': longest.name,
      'waitingMinutes': DateTime.now().difference(longest.arrivalTime).inMinutes
    };
  }

  Map<String, dynamic> getQueueOverview() {
    if (_isDisposed) throw Exception('Scheduler is disposed');
    final waiting = _getWaitingPatients();

    return {
      'status': 'success',
      'message': 'Queue overview',
      'data': {
        'doctorStatus':
            isDoctorOnBreak ? 'Doctor on Break' : 'Doctor Available',
        'currentPatient': currentPatient?.name ?? 'None',
        'queueLength': waiting.length,
        'nextPatients': waiting
            .take(5)
            .map((p) => {
                  'id': p.id,
                  'name': p.name,
                  'position': _getQueuePosition(p),
                  'estimatedWait': isDoctorOnBreak
                      ? 'Doctor on break'
                      : '${_calculateWaitingTime(p)} mins'
                })
            .toList(),
        'averageWaitTime': isDoctorOnBreak
            ? 'Doctor on break'
            : '${averageConsultationTime.round()} mins per patient',
        'lastUpdated': DateTime.now().toString(),
        'isLoading': _isLoading,
      }
    };
  }

  // Add this getter for UI compatibility
  int? get currentPatientNumber =>
      currentPatient != null ? _getQueuePosition(currentPatient!) : null;

  void dispose() {
    _isDisposed = true;
    patients.clear();
    currentPatient = null;
  }
}
