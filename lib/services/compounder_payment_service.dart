import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

/// Service to handle Compounder payment records and retention policy.
class CompounderPaymentService {
  // Follow requested naming: 'compunder pay' (spaces not allowed) -> 'compunder_pay'
  static const String collectionName = 'compunder_pay';

  final FirebaseFirestore _db;

  CompounderPaymentService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  /// Adds a payment record and enforces a two-day retention policy
  /// (keeps only today and yesterday; deletes anything older).
  Future<void> addPaymentRecord({
    required String patientToken,
    required String patientName,
    required String mobileNumber,
    required int age,
    required String method, // 'cash' or 'online'
  }) async {
    final now = DateTime.now();
    final dateStr = DateFormat('yyyy-MM-dd').format(now);

    await _db.collection(collectionName).add({
      'patientToken': patientToken,
      'patientName': patientName,
      'mobileNumber': mobileNumber,
      'age': age,
      'method': method.toLowerCase(),
      'date': dateStr,
      'timestamp': FieldValue.serverTimestamp(),
    });

    await _cleanupOldPayments();
  }

  /// Returns payments for today and previous 2 days (3 days total).
  Stream<List<Map<String, dynamic>>> paymentsForLast3Days() {
    final now = DateTime.now();
    final d0 = DateFormat('yyyy-MM-dd').format(now);
    final d1 =
        DateFormat('yyyy-MM-dd').format(now.subtract(const Duration(days: 1)));
    final d2 =
        DateFormat('yyyy-MM-dd').format(now.subtract(const Duration(days: 2)));

    return _db
        .collection(collectionName)
        .where('date', whereIn: [d2, d1, d0])
        .orderBy('date', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.data()).toList());
  }

  /// Deletes any payments older than yesterday (keeps only today and yesterday).
  Future<void> _cleanupOldPayments() async {
    // Keep today and previous 2 days → delete anything older than start of (today - 2)
    final threeDaysAgo = DateTime.now().subtract(const Duration(days: 2));
    final cutoff =
        DateTime(threeDaysAgo.year, threeDaysAgo.month, threeDaysAgo.day);

    try {
      final old = await _db
          .collection(collectionName)
          .where('timestamp', isLessThan: Timestamp.fromDate(cutoff))
          .get();
      final batch = _db.batch();
      for (final doc in old.docs) {
        batch.delete(doc.reference);
      }
      if (old.docs.isNotEmpty) {
        await batch.commit();
      }
    } catch (e) {
      // Ignore cleanup errors to not block booking flow
    }
  }
}
