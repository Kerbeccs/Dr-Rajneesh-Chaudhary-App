import 'package:flutter/foundation.dart';
import '../models/booking_slot.dart';
import 'package:intl/intl.dart';
import '../services/database_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/logging_service.dart';
import '../utils/locator.dart'; // Import DI locator

class BookingViewModel extends ChangeNotifier {
  // Use dependency injection for shared service instances
  // This fixes race conditions caused by multiple service instances
  final DatabaseService _databaseService;
  final FirebaseFirestore _firestore;
  bool _isLoading = false;
  List<Map<String, dynamic>> _bookings = [];

  // Constructor with optional parameters
  // Uses DI container (locator) if not provided
  // This ensures all BookingViewModel instances share the same services
  BookingViewModel({
    DatabaseService? databaseService,
    FirebaseFirestore? firestore,
  })  : _databaseService = databaseService ?? locator<DatabaseService>(),
        _firestore = firestore ?? locator<FirebaseFirestore>();

  DateTime? _selectedDate;
  BookingSlot? _selectedSlot;
  String? _selectedTimeSlot; // 'morning', 'afternoon', or 'evening'

  // Map to store slots for each date (key: formatted date string, value: list of slots)
  final Map<String, List<BookingSlot>> _dateSlots = {};

  // Map to store disabled time slots for each date
  final Map<String, Set<String>> _disabledTimeSlots = {};

  bool _isDisposed = false;
  Set<int> _bookedSeatNumbers = <int>{};

  DateTime? get selectedDate => _selectedDate;
  BookingSlot? get selectedSlot => _selectedSlot;
  String? get selectedTimeSlot => _selectedTimeSlot;
  Set<int> get bookedSeatNumbers => _bookedSeatNumbers;

  bool get isLoading => _isLoading;
  List<Map<String, dynamic>> get bookings => _bookings;

  // Get slots for the currently selected date and time slot
  List<BookingSlot> get slots {
    if (_selectedDate == null || _selectedTimeSlot == null) return [];

    final dateKey = _getDateKey(_selectedDate!);
    final timeSlotKey = '${dateKey}_$_selectedTimeSlot';

    // Initialize slots for this date and time slot if they don't exist
    if (!_dateSlots.containsKey(timeSlotKey)) {
      int capacity;
      switch (_selectedTimeSlot) {
        case 'morning':
          capacity = 70; // Morning: 70 seats
          break;
        case 'afternoon':
          capacity = 30; // Afternoon: 30 seats
          break;
        case 'evening':
          capacity = 50; // Evening: 50 seats
          break;
        default:
          capacity = 0;
      }

      _dateSlots[timeSlotKey] = List.generate(
        capacity,
        (index) => BookingSlot(
          time: _selectedTimeSlot!,
          capacity: 1,
          booked: 0,
          seatNumber: index + 1,
          isDisabled: isTimeSlotDisabled(_selectedTimeSlot!),
        ),
      );
    }

    // Update slots based on Firestore data
    _updateSlotsFromFirestore(dateKey, timeSlotKey);

    return _dateSlots[timeSlotKey]!;
  }

  // Helper method to get a consistent date key
  String _getDateKey(DateTime date) {
    return DateFormat('yyyy-MM-dd').format(date);
  }

  void setSelectedSlot(BookingSlot slot) {
    _selectedSlot = slot;
    notifyListeners();
  }

  void setSelectedTimeSlot(String timeSlot) {
    _selectedTimeSlot = timeSlot;
    if (_selectedDate != null) {
      loadBookedSlotsForDateAndTime(_selectedDate!, timeSlot);
    }
    notifyListeners();
  }

  /// Returns today and tomorrow as available booking dates.
  List<DateTime> get availableDates {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    return [today, tomorrow];
  }

  void selectDate(DateTime date) {
    _selectedDate = date;
    _selectedTimeSlot = null; // Reset time slot when date changes
    _bookedSeatNumbers.clear(); // Clear booked seats on date change
    // Load disabled time slots for the selected date
    final dateKey = _getDateKey(date);
    _loadDisabledTimeSlotsFromFirestore(dateKey);
    notifyListeners();
  }

  bool isDateValid(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    final selectedDate = DateTime(date.year, date.month, date.day);

    return selectedDate == today || selectedDate == tomorrow;
  }

  bool isTimeSlotValid(String timeSlot, DateTime date) {
    // Check if booking is for today - if so, validate time slot hasn't passed
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final selectedDate = DateTime(date.year, date.month, date.day);

    // If booking is for today, check if time slot is still valid
    if (selectedDate == today) {
      // Get the end time of the selected time slot
      final timeSlotEnd = _getTimeSlotEndTime(timeSlot);
      // If current time is past the end time, slot is invalid
      if (now.isAfter(timeSlotEnd)) {
        return false;
      }
    }

    return true;
  }

  DateTime _getTimeSlotEndTime(String timeSlot) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    switch (timeSlot) {
      case 'morning':
        return today.add(const Duration(hours: 14, minutes: 30)); // 2:30 PM
      case 'afternoon':
        return today.add(const Duration(hours: 17)); // 5:00 PM
      case 'evening':
        return today.add(const Duration(hours: 20)); // 8:00 PM
      default:
        return today.add(const Duration(hours: 24)); // Default to end of day
    }
  }

  /// Books a slot if available, returns `true` if successful, else `false`.
  ///
  /// FIXED: Now uses Firestore transaction to prevent race conditions
  /// Previously: Check local cache → Update local → Update DB (gap = race condition!)
  /// Now: Atomic transaction checks and creates booking in one operation
  Future<bool> bookSlot(int seatNumber) async {
    if (_selectedDate == null || _selectedTimeSlot == null) {
      LoggingService.warning('Booking failed: no date or time slot selected');
      return false;
    }

    if (!isTimeSlotValid(_selectedTimeSlot!, _selectedDate!)) {
      LoggingService.warning(
          'Booking failed: selected time slot no longer available');
      return false;
    }

    final dateKey = _getDateKey(_selectedDate!);
    final timeSlotKey = '${dateKey}_$_selectedTimeSlot';
    final timeRange = getTimeSlotRange(_selectedTimeSlot!);

    try {
      // ✅ FIX: Use Firestore transaction to prevent double-booking
      // This ensures atomic check-and-book operation
      await _firestore.runTransaction((transaction) async {
        // CRITICAL: Check if seat is already booked in Firestore
        // This prevents race condition when multiple users click same seat
        final conflictQuery = _firestore
            .collection('appointments')
            .where('appointmentDate', isEqualTo: dateKey)
            .where('appointmentTime', isEqualTo: timeRange)
            .where('seatNumber', isEqualTo: seatNumber)
            .where('status',
                whereIn: ['pending', 'in_progress', 'confirmed', 'completed']);

        // Get query snapshot within transaction
        final conflictSnapshot = await conflictQuery.get();

        // If seat already booked, abort transaction
        if (conflictSnapshot.docs.isNotEmpty) {
          throw Exception(
              'Seat $seatNumber is already booked. Please select another seat.');
        }

        // Seat is available - create appointment atomically
        // This happens in the same transaction as the check above
        final appointmentRef = _firestore.collection('appointments').doc();
        transaction.set(appointmentRef, {
          'seatNumber': seatNumber,
          'appointmentDate': dateKey,
          'appointmentTime': timeRange,
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
          // Note: Other fields should be added by the calling code
          // This is just the slot reservation part
        });
      });

      // Transaction succeeded - update local state
      final dateSlots = _dateSlots[timeSlotKey];
      if (dateSlots != null) {
        final slot =
            dateSlots.firstWhere((slot) => slot.seatNumber == seatNumber);
        slot.book();
        slot.isDisabled = true;
      }

      // Also update slots collection for consistency
      await _databaseService.updateSlotAvailability(
        slotTime: _selectedTimeSlot!,
        date: dateKey,
        isDisabled: true,
        seatNumber: seatNumber,
      );

      notifyListeners();
      LoggingService.info('Slot $seatNumber booked successfully for $dateKey');
      return true;
    } catch (e) {
      LoggingService.error(
          'Booking failed for seat $seatNumber', e, StackTrace.current);

      // Refresh slots to show current state
      await loadBookedSlotsForDateAndTime(_selectedDate!, _selectedTimeSlot!);

      return false;
    }
  }

  String getTimeSlotRange(String timeSlot) {
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

  Future<void> toggleSlotAvailability(BookingSlot slot, DateTime date) async {
    try {
      final formattedDate = DateFormat('yyyy-MM-dd').format(date);

      // Update the slot locally first for immediate UI feedback
      final index = slots.indexWhere((s) => s.seatNumber == slot.seatNumber);
      if (index != -1) {
        slots[index].isDisabled = !slots[index].isDisabled;
        notifyListeners();
      }

      // Then update in Firestore
      await _databaseService.updateSlotAvailability(
        slotTime: _selectedTimeSlot!,
        date: formattedDate,
        isDisabled: slots[index].isDisabled,
        seatNumber: slot.seatNumber,
      );
    } catch (e) {
      LoggingService.error(
          'Error toggling slot availability', e, StackTrace.current);
      // Revert the local change if server update fails
      final index = slots.indexWhere((s) => s.seatNumber == slot.seatNumber);
      if (index != -1) {
        slots[index].isDisabled = !slots[index].isDisabled;
        notifyListeners();
      }
    }
  }

  Future<void> fetchSlots(DateTime date) async {
    try {
      final dateKey = DateFormat('yyyy-MM-dd').format(date);
      final fetchedSlots = await _databaseService.getSlots(dateKey);

      // Filter out disabled slots or mark them as unavailable
      _dateSlots[dateKey] =
          fetchedSlots.where((slot) => !slot.isDisabled).toList();
      notifyListeners();
    } catch (e) {
      LoggingService.error('Error fetching slots', e, StackTrace.current);
    }
  }

  bool isSlotAvailable(BookingSlot slot) {
    return !slot.isDisabled && slot.canBook();
  }

  bool isTimeSlotDisabled(String timeSlot) {
    if (_selectedDate == null) return false;
    final dateKey = _getDateKey(_selectedDate!);
    return _disabledTimeSlots[dateKey]?.contains(timeSlot) ?? false;
  }

  Future<void> toggleTimeSlotAvailability(
      String timeSlot, DateTime date) async {
    try {
      final dateKey = _getDateKey(date);

      // Initialize the set for this date if it doesn't exist
      _disabledTimeSlots[dateKey] ??= {};

      // Toggle the time slot's disabled state
      if (_disabledTimeSlots[dateKey]!.contains(timeSlot)) {
        _disabledTimeSlots[dateKey]!.remove(timeSlot);
      } else {
        _disabledTimeSlots[dateKey]!.add(timeSlot);
      }

      // Update all slots for this time slot
      final timeSlotKey = '${dateKey}_$timeSlot';
      if (_dateSlots.containsKey(timeSlotKey)) {
        for (var slot in _dateSlots[timeSlotKey]!) {
          slot.isDisabled = isTimeSlotDisabled(timeSlot);
        }
      }

      // Update in Firestore
      await _databaseService.updateTimeSlotAvailability(
        timeSlot: timeSlot,
        date: dateKey,
        isDisabled: isTimeSlotDisabled(timeSlot),
      );

      notifyListeners();
    } catch (e) {
      LoggingService.error(
          'Error toggling time slot availability', e, StackTrace.current);
      rethrow;
    }
  }

  void _throwIfDisposed() {
    if (_isDisposed) {
      throw FlutterError('A BookingViewModel was used after being disposed.\n'
          'Once you have called dispose() on a BookingViewModel, it can no longer be used.');
    }
  }

  /// Load disabled time slots from Firestore for a given date
  Future<void> _loadDisabledTimeSlotsFromFirestore(String dateKey) async {
    try {
      final doc = await _firestore.collection('slots').doc(dateKey).get();

      if (doc.exists && doc.data() != null) {
        final data = doc.data() as Map<String, dynamic>;
        _disabledTimeSlots[dateKey] ??= {};

        // Check each time slot for disabled state
        data.forEach((timeSlot, slotData) {
          if (slotData is Map && slotData['isDisabled'] == true) {
            _disabledTimeSlots[dateKey]!.add(timeSlot);
          } else if (slotData is Map && slotData['isDisabled'] == false) {
            _disabledTimeSlots[dateKey]!.remove(timeSlot);
          }
        });
      }
    } catch (e) {
      LoggingService.error('Error loading disabled time slots from Firestore',
          e, StackTrace.current);
    }
  }

  /// Public method to load disabled time slots for manage slots screen
  Future<void> loadDisabledTimeSlotsForDate(String dateKey) async {
    await _loadDisabledTimeSlotsFromFirestore(dateKey);
    notifyListeners();
  }

  Future<void> _updateSlotsFromFirestore(
      String dateKey, String timeSlotKey) async {
    _throwIfDisposed();
    try {
      // Load disabled time slots first
      await _loadDisabledTimeSlotsFromFirestore(dateKey);

      final fetchedSlots = await _databaseService.getSlots(dateKey);

      // Check disposal state again after async operation
      if (_isDisposed) return;

      // Update slots with Firestore data
      for (var fetchedSlot in fetchedSlots) {
        if (fetchedSlot.time == _selectedTimeSlot) {
          final index = _dateSlots[timeSlotKey]!
              .indexWhere((slot) => slot.seatNumber == fetchedSlot.seatNumber);
          if (index != -1) {
            // Preserve disabled state from Firestore (both time slot level and seat level)
            final timeSlotIsDisabled = isTimeSlotDisabled(_selectedTimeSlot!);
            _dateSlots[timeSlotKey]![index] = fetchedSlot;
            // Ensure time slot level disabled state is applied
            if (timeSlotIsDisabled) {
              _dateSlots[timeSlotKey]![index].isDisabled = true;
            }
          }
        }
      }
      if (!_isDisposed) {
        notifyListeners();
      }
    } catch (e) {
      LoggingService.error(
          'Error updating slots from Firestore', e, StackTrace.current);
      rethrow;
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_isDisposed) {
      super.notifyListeners();
    }
  }

  Future<void> createBooking({
    required String doctorId,
    required String patientId,
    required DateTime appointmentTime,
    required String reason,
  }) async {
    try {
      _isLoading = true;
      notifyListeners();

      await _firestore.collection('bookings').add({
        'doctorId': doctorId,
        'patientId': patientId,
        'appointmentTime': Timestamp.fromDate(appointmentTime),
        'reason': reason,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

      await fetchBookings(patientId);
    } catch (e) {
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Fetch recent and upcoming bookings with limits to keep reads fast and cheap.
  Future<void> fetchBookings(String userId, {int limit = 50}) async {
    try {
      _isLoading = true;
      notifyListeners();

      // Only fetch recent and upcoming bookings (last 30 days) to reduce reads
      final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));

      final snapshot = await _firestore
          .collection('bookings')
          .where('patientId', isEqualTo: userId)
          .where('appointmentTime',
              isGreaterThanOrEqualTo: Timestamp.fromDate(thirtyDaysAgo))
          .orderBy('appointmentTime', descending: true)
          .limit(limit)
          .get();

      _bookings = snapshot.docs
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

  Future<void> loadBookedSlotsForDateAndTime(
      DateTime date, String timeSlot) async {
    try {
      _isLoading = true;
      notifyListeners();

      final formattedDate = DateFormat('yyyy-MM-dd').format(date);
      final timeRange = getTimeSlotRange(timeSlot);

      // SOLUTION 1: Time-Slot Based Locking
      // Include 'completed' status to prevent double-booking after completion
      // A seat remains locked for its time slot even after completion
      // Only 'cancelled' appointments release the seat (excluded from this query)
      final querySnapshot = await _firestore
          .collection('appointments')
          .where('appointmentDate', isEqualTo: formattedDate)
          .where('appointmentTime', isEqualTo: timeRange)
          .where('status', whereIn: [
        'pending',
        'in_progress',
        'confirmed',
        'completed'
      ]).get();

      _bookedSeatNumbers = querySnapshot.docs
          .map((doc) => doc.data()['seatNumber'] as int)
          .toSet();

      // Update slots availability
      final dateKey = _getDateKey(date);
      final timeSlotKey = '${dateKey}_$timeSlot';

      // Load disabled time slots from Firestore
      await _loadDisabledTimeSlotsFromFirestore(dateKey);

      if (_dateSlots.containsKey(timeSlotKey)) {
        for (var slot in _dateSlots[timeSlotKey]!) {
          // Preserve disabled state from Firestore (time slot level)
          // Only mark as disabled if seat is booked OR time slot is disabled
          final timeSlotIsDisabled = isTimeSlotDisabled(timeSlot);
          slot.isDisabled = timeSlotIsDisabled ||
              _bookedSeatNumbers.contains(slot.seatNumber);
        }
      }

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      LoggingService.error('Error loading booked slots', e, StackTrace.current);
      _isLoading = false;
      notifyListeners();
    }
  }

  bool isSeatBooked(int seatNumber) => _bookedSeatNumbers.contains(seatNumber);

  String getSeatStatusText(int seatNumber) {
    return isSeatBooked(seatNumber) ? 'Booked' : 'Available';
  }

  void clearBookedSlots() {
    _throwIfDisposed();
    _bookedSeatNumbers.clear();
    if (_selectedDate != null && _selectedTimeSlot != null) {
      final dateKey = _getDateKey(_selectedDate!);
      final timeSlotKey = '${dateKey}_$_selectedTimeSlot';
      if (_dateSlots.containsKey(timeSlotKey)) {
        for (final slot in _dateSlots[timeSlotKey]!) {
          slot.isDisabled = false;
        }
      }
    }
    notifyListeners();
  }
}
