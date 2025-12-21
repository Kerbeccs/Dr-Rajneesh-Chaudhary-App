import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import '../models/report_model.dart';
import '../models/booking_slot.dart';
import '../models/feedback_model.dart';
import '../models/patient_record.dart';
import 'logging_service.dart';

class DatabaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Patients Collection Methods
  Future<void> updatePatient(UserModel patient) async {
    await _db.collection('users').doc(patient.uid).set(patient.toMap());
  }

  Future<UserModel?> getPatient(String patientId) async {
    final doc = await _db.collection('users').doc(patientId).get();
    if (doc.exists) {
      return UserModel.fromMap(doc.data()!);
    }
    return null;
  }

  // Reports Collection Methods
  Future<String> addReport(ReportModel report) async {
    try {
      LoggingService.info('Adding report for patient: ${report.patientId}');
      LoggingService.debug('Full report data: ${report.toMap()}');

      final docRef = _db.collection('reports').doc();
      final reportWithId = ReportModel(
        reportId: docRef.id,
        patientId: report.patientId,
        description: report.description,
        fileUrl: report.fileUrl,
        uploadedAt: report.uploadedAt,
      );

      await docRef.set(reportWithId.toMap());
      LoggingService.info('Report saved with ID: ${docRef.id}');
      return docRef.id;
    } catch (e, st) {
      LoggingService.error('Error saving report', e, st);
      rethrow;
    }
  }

  // Fetch recent reports for a patient with an optional limit to control read volume.
  Future<List<ReportModel>> getPatientReports(String patientId,
      {int limit = 20}) async {
    try {
      LoggingService.debug('Fetching reports for patient ID: $patientId');

      // First get the patient data to get the lastVisited field so it can be shown with reports
      final patientDoc = await _db.collection('users').doc(patientId).get();
      String? lastVisited;

      if (patientDoc.exists) {
        final patientData = patientDoc.data();
        lastVisited = patientData?['lastVisited'];
        LoggingService.debug('Patient last visited: $lastVisited');
      }

      // Get recent reports for specific patient with a sane limit to reduce reads
      final querySnapshot = await _db
          .collection('reports')
          .where('patientId', isEqualTo: patientId)
          .orderBy('uploadedAt', descending: true)
          .limit(limit)
          .get();

      LoggingService.debug(
          'Found ${querySnapshot.docs.length} reports for this patient');

      if (querySnapshot.docs.isNotEmpty) {
        LoggingService.debug(
            'Sample report data: ${querySnapshot.docs.first.data()}');
      }

      // Map the reports and include the lastVisited field
      return querySnapshot.docs.map((doc) {
        final reportData = doc.data();
        return ReportModel(
          reportId: reportData['reportId'] ?? '',
          patientId: reportData['patientId'] ?? '',
          description: reportData['description'] ?? '',
          fileUrl: reportData['fileUrl'] ?? '',
          uploadedAt: DateTime.parse(reportData['uploadedAt']),
          lastVisited: lastVisited, // Include the lastVisited field
        );
      }).toList();
    } catch (e) {
      LoggingService.error('Error fetching reports', e, StackTrace.current);
      return [];
    }
  }

  // Update last visited
  Future<void> updateLastVisited(String patientId) async {
    await _db.collection('users').doc(patientId).update({
      'lastVisited': DateTime.now().toIso8601String(),
    });
  }

  Future<List<UserModel>> getAllPatients() async {
    try {
      final querySnapshot = await _db
          .collection('users')
          .where('userType', isEqualTo: 'patient')
          .get();

      LoggingService.info('Found ${querySnapshot.docs.length} patients');
      LoggingService.debug(
          'Patient names: ${querySnapshot.docs.map((doc) => doc.data()['patientName'])}');

      return querySnapshot.docs
          .map((doc) => UserModel.fromMap(doc.data()))
          .toList();
    } catch (e) {
      LoggingService.error('Error fetching patients', e, StackTrace.current);
      return [];
    }
  }

  Future<void> deleteReport(String reportId) async {
    try {
      await _db.collection('reports').doc(reportId).delete();
    } catch (e) {
      LoggingService.error(
          'Error deleting report from Firestore', e, StackTrace.current);
      rethrow;
    }
  }

  Future<void> updateSlotAvailability({
    required String slotTime,
    required String date,
    required bool isDisabled,
    required int seatNumber,
  }) async {
    try {
      final docRef = _db.collection('slots').doc(date);
      final doc = await docRef.get();

      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        if (data.containsKey(slotTime)) {
          final slotData = data[slotTime] as Map<String, dynamic>;
          slotData['isDisabled'] = isDisabled;
          await docRef.update({slotTime: slotData});
        }
      }
    } catch (e) {
      LoggingService.error(
          'Error updating slot availability', e, StackTrace.current);
      rethrow;
    }
  }

  Future<void> updateSlotBooking({
    required String date,
    required String timeSlot,
    required int seatNumber,
    required bool isBooked,
  }) async {
    try {
      final docRef = _db.collection('slots').doc(date);
      final doc = await docRef.get();

      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        if (data.containsKey(timeSlot)) {
          final slotData = data[timeSlot] as Map<String, dynamic>;
          if (slotData['seats'] is Map) {
            final seats = slotData['seats'] as Map<String, dynamic>;
            seats[seatNumber.toString()] = {
              'isBooked': isBooked,
              'isDisabled': isBooked, // Disable the slot if it's booked
              'bookedAt': isBooked ? FieldValue.serverTimestamp() : null,
            };
            await docRef.update({
              '$timeSlot.seats': seats,
            });
          }
        }
      }
    } catch (e) {
      LoggingService.error(
          'Error updating slot booking', e, StackTrace.current);
      rethrow;
    }
  }

  Future<List<BookingSlot>> getSlots(String dateKey) async {
    try {
      final doc = await _db.collection('slots').doc(dateKey).get();

      if (doc.exists && doc.data() != null) {
        final data = doc.data() as Map<String, dynamic>;
        final List<BookingSlot> slots = [];

        // Convert Firestore data to BookingSlot objects
        data.forEach((time, slotData) {
          if (slotData is Map) {
            if (slotData['seats'] is Map) {
              final seats = slotData['seats'] as Map<String, dynamic>;
              seats.forEach((seatNumber, seatData) {
                if (seatData is Map) {
                  slots.add(BookingSlot(
                    time: time,
                    capacity: 1,
                    booked: seatData['isBooked'] == true ? 1 : 0,
                    isDisabled: seatData['isDisabled'] == true ||
                        slotData['isDisabled'] == true,
                    seatNumber: int.parse(seatNumber),
                  ));
                }
              });
            }
          }
        });

        return slots;
      }
      return [];
    } catch (e) {
      LoggingService.error('Error fetching slots', e, StackTrace.current);
      return [];
    }
  }

  // Feedback Collection Methods
  Future<String> addFeedback(FeedbackModel feedback) async {
    try {
      LoggingService.info(
          'Adding feedback from patient: ${feedback.patientId}');

      // Set feedback to expire after 7 days (1 week)
      final docRef = _db.collection('feedback').doc();
      final feedbackWithId = FeedbackModel(
        id: docRef.id,
        patientId: feedback.patientId,
        patientName: feedback.patientName,
        comment: feedback.comment,
        rating: feedback.rating,
        createdAt: feedback.createdAt,
      );

      await docRef.set(feedbackWithId.toMap());
      LoggingService.info('Feedback saved with ID: ${docRef.id}');

      // Schedule the feedback to be deleted after 7 days
      // Note: We're not actually deleting it here, but we'll filter by date when retrieving

      return docRef.id;
    } catch (e) {
      LoggingService.error('Error saving feedback', e, StackTrace.current);
      rethrow;
    }
  }

  Future<List<FeedbackModel>> getActiveFeedback() async {
    try {
      // Get current date and calculate date 7 days ago
      final now = DateTime.now();
      final oneWeekAgo = now.subtract(const Duration(days: 7));

      // Get feedback that's less than 7 days old
      final querySnapshot = await _db
          .collection('feedback')
          .where('createdAt',
              isGreaterThanOrEqualTo: oneWeekAgo.toIso8601String())
          .get();

      LoggingService.info(
          'Found ${querySnapshot.docs.length} active feedback in last 7 days');

      return querySnapshot.docs.map((doc) {
        return FeedbackModel.fromMap(doc.data());
      }).toList();
    } catch (e) {
      LoggingService.error('Error fetching feedback', e, StackTrace.current);
      return [];
    }
  }

  Future<void> updateTimeSlotAvailability({
    required String timeSlot,
    required String date,
    required bool isDisabled,
  }) async {
    try {
      final docRef = _db.collection('slots').doc(date);
      final doc = await docRef.get();

      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        if (data.containsKey(timeSlot)) {
          final slotData = data[timeSlot] as Map<String, dynamic>;
          // Update all seats in this time slot
          if (slotData['seats'] is Map) {
            final seats = slotData['seats'] as Map<String, dynamic>;
            seats.forEach((seatNumber, seatData) {
              seatData['isDisabled'] = isDisabled;
            });
            await docRef.update({
              '$timeSlot.seats': seats,
              '$timeSlot.isDisabled': isDisabled,
            });
          }
        } else {
          // Create new time slot entry if it doesn't exist
          await docRef.set({
            timeSlot: {
              'isDisabled': isDisabled,
              'seats': {},
            }
          }, SetOptions(merge: true));
        }
      } else {
        // Create new document if it doesn't exist
        await docRef.set({
          timeSlot: {
            'isDisabled': isDisabled,
            'seats': {},
          }
        });
      }
    } catch (e) {
      LoggingService.error(
          'Error updating time slot availability', e, StackTrace.current);
      rethrow;
    }
  }

  // ---------------- Patients collection (separate from users) ----------------
  CollectionReference<Map<String, dynamic>> get _patientsCol =>
      _db.collection('patients');
  DocumentReference<Map<String, dynamic>> get _countersDoc =>
      _db.collection('meta').doc('counters');

  Future<PatientRecord?> getPatientByToken(String tokenId) async {
    try {
      final snap = await _patientsCol
          .where('tokenId', isEqualTo: tokenId)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return null;
      return PatientRecord.fromMap(snap.docs.first.data());
    } catch (e) {
      LoggingService.error('Error getPatientByToken', e, StackTrace.current);
      return null;
    }
  }

  Future<bool> isFeeValidWithinDays(PatientRecord record,
      {int days = 7}) async {
    if (record.lastVisited == null) return false;
    final now = DateTime.now();
    return now.difference(record.lastVisited!).inDays < days;
  }

  // Generate simple, unique, human-friendly token based on counter
  // Format: PAT000001, PAT000002, ...
  Future<String> generateNewToken() async {
    return await _db.runTransaction((txn) async {
      final counterSnap = await txn.get(_countersDoc);
      int next = 1;
      if (counterSnap.exists) {
        final data = counterSnap.data() as Map<String, dynamic>;
        next = (data['patientCounter'] ?? 0) + 1;
      }
      txn.set(_countersDoc, {'patientCounter': next}, SetOptions(merge: true));
      final token = 'PAT${next.toString().padLeft(6, '0')}';
      return token;
    });
  }

  /// Check how many token IDs a user has created (max 7 allowed)
  Future<int> getTokenIdCountForUser(String? userPhoneNumber) async {
    if (userPhoneNumber == null || userPhoneNumber.isEmpty) {
      return 0;
    }

    try {
      // Build phone variants to match different formats
      final variants = _buildPhoneVariants(userPhoneNumber);

      // Query by userPhoneNumber
      final query =
          await _patientsCol.where('userPhoneNumber', whereIn: variants).get();

      return query.docs.length;
    } catch (e) {
      LoggingService.error('Error counting token IDs', e, StackTrace.current);
      return 0;
    }
  }

  /// Build phone number variants for matching (same logic as in patient_dashboard)
  List<String> _buildPhoneVariants(String raw) {
    String trimmed = raw.trim();
    final Set<String> out = {trimmed};

    // Strip non-digits except leading '+'
    final onlyDigits = trimmed.replaceAll(RegExp(r"[^0-9+]"), '');
    out.add(onlyDigits);

    // Remove '+' for digit-only processing
    final digits =
        onlyDigits.startsWith('+') ? onlyDigits.substring(1) : onlyDigits;

    // If number has leading 0 and total 11, also add last 10
    if (digits.length == 11 && digits.startsWith('0')) {
      out.add(digits.substring(1));
    }

    // If 10-digit local number, add '+91' prefixed version
    if (digits.length == 10) {
      out.add('+91$digits');
      out.add('91$digits');
    }

    // If begins with '91' and total 12, add '+91' prefixed
    if (digits.length == 12 && digits.startsWith('91')) {
      out.add('+$digits');
      out.add(digits.substring(2)); // also local 10-digit
    }

    // If already starts with '+', add without plus variant
    if (onlyDigits.startsWith('+')) {
      out.add(onlyDigits.substring(1));
    } else {
      // Add '+' variant
      out.add('+$onlyDigits');
    }

    // Firestore whereIn max 10; keep first up to 10
    return out.where((s) => s.isNotEmpty).take(10).toList();
  }

  Future<String> createPatientAfterPayment({
    required String name,
    required String mobileNumber,
    required int age,
    required String aadhaarLast4,
    String? sex,
    int? weightKg,
    String? userPhoneNumber,
  }) async {
    try {
      // Check token ID limit (max 7 per user phone number)
      if (userPhoneNumber != null && userPhoneNumber.isNotEmpty) {
        final currentCount = await getTokenIdCountForUser(userPhoneNumber);
        if (currentCount >= 7) {
          throw Exception(
              'Maximum limit reached. You can create only 7 token IDs per phone number. Please use an existing token ID or contact support.');
        }
      }

      final token = await generateNewToken();
      final record = PatientRecord(
        tokenId: token,
        name: name,
        mobileNumber: mobileNumber,
        age: age,
        aadhaarLast4: aadhaarLast4,
        sex: sex,
        weightKg: weightKg,
        userPhoneNumber: userPhoneNumber,
        createdAt: DateTime.now(),
        lastVisited: DateTime.now(), // set on first successful payment
        updatedAt: DateTime.now(),
      );
      await _patientsCol.doc(token).set(record.toMap());
      return token;
    } catch (e) {
      LoggingService.error(
          'Error createPatientAfterPayment', e, StackTrace.current);
      rethrow;
    }
  }

  Future<void> updatePatientLastVisited(String tokenId) async {
    try {
      await _patientsCol.doc(tokenId).set({
        'lastVisited': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String()
      }, SetOptions(merge: true));
    } catch (e) {
      LoggingService.error(
          'Error updatePatientLastVisited', e, StackTrace.current);
      rethrow;
    }
  }

  // Paginated patients list for doctor dashboard to avoid loading thousands at once.
  Future<List<PatientRecord>> getAllPatientsForDoctorDashboard(
      {int limit = 50,
      DocumentSnapshot<Map<String, dynamic>>? lastDocument}) async {
    try {
      // Build a paginated query ordered by creation time
      Query<Map<String, dynamic>> query =
          _patientsCol.orderBy('createdAt', descending: true).limit(limit);

      // When a last document is provided, continue after it for pagination
      if (lastDocument != null) {
        query = query.startAfterDocument(lastDocument);
      }

      final snap = await query.get();
      return snap.docs.map((d) => PatientRecord.fromMap(d.data())).toList();
    } catch (e) {
      LoggingService.error(
          'Error getAllPatientsForDoctorDashboard', e, StackTrace.current);
      return [];
    }
  }

  // Helper to fetch the last document for a given offset to drive pagination UI
  Future<DocumentSnapshot<Map<String, dynamic>>?> getLastPatientSnapshot(
      int offset) async {
    try {
      final snap = await _patientsCol
          .orderBy('createdAt', descending: true)
          .limit(offset)
          .get();
      return snap.docs.isNotEmpty ? snap.docs.last : null;
    } catch (e) {
      LoggingService.error(
          'Error getting last snapshot', e, StackTrace.current);
      return null;
    }
  }

  // Delete feedback older than 7 days to keep the collection lean
  Future<void> deleteOldFeedback() async {
    try {
      final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));

      // Fetch all feedback docs older than 7 days
      final querySnapshot = await _db
          .collection('feedback')
          .where('createdAt', isLessThan: sevenDaysAgo.toIso8601String())
          .get();

      // Batch delete in chunks of 500 (Firestore limit)
      final batches = <WriteBatch>[];
      var currentBatch = _db.batch();
      var operationCount = 0;

      for (var doc in querySnapshot.docs) {
        currentBatch.delete(doc.reference);
        operationCount++;

        if (operationCount == 500) {
          batches.add(currentBatch);
          currentBatch = _db.batch();
          operationCount = 0;
        }
      }

      if (operationCount > 0) {
        batches.add(currentBatch);
      }

      for (var batch in batches) {
        await batch.commit();
      }

      LoggingService.info(
          'Deleted ${querySnapshot.docs.length} old feedback records in ${batches.length} batches');
    } catch (e) {
      LoggingService.error(
          'Error deleting old feedback', e, StackTrace.current);
    }
  }
}
