import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../viewmodels/booking_view_model.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../services/whatsapp_service.dart';
import '../../models/booking_slot.dart';
import '../../services/database_service.dart';
import '../../services/compounder_payment_service.dart';
import '../../services/logging_service.dart';

class BookingScreen extends StatefulWidget {
  final bool
      isCompounderMode; // if true, replace Razorpay with manual Cash/Online
  const BookingScreen({super.key, this.isCompounderMode = false});

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  late Razorpay _razorpay;
  late BookingViewModel _bookingViewModel;
  late AuthViewModel _authViewModel;
  bool _isProcessingPayment = false;
  bool _isInitialized = false;
  final CompounderPaymentService _compounderPaymentService =
      CompounderPaymentService();

  // Pre-booking flow state
  final DatabaseService _db = DatabaseService();
  String? _pendingExistingTokenId;
  Map<String, dynamic>?
      _pendingNewPatientData; // {name, mobile, age, aadhaarLast4}
  BookingSlot? _pendingSlot;
  DateTime? _pendingDate;
  String? _pendingTimeSlotKey; // e.g. 'morning'

  @override
  void initState() {
    super.initState();
    if (!widget.isCompounderMode) {
      _initializeRazorpay();
    }
    _initializeViewModels();
  }

  void _initializeRazorpay() {
    try {
      print("Initializing Razorpay");
      _razorpay = Razorpay();
      _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
      _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
      _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
    } catch (e) {
      print('Error initializing Razorpay: $e');
      _showErrorSnackBar('Payment system initialization failed');
    }
  }

  void _initializeViewModels() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        _bookingViewModel =
            Provider.of<BookingViewModel>(context, listen: false);
        _authViewModel = Provider.of<AuthViewModel>(context, listen: false);
        setState(() {
          _isInitialized = true;
        });
      } catch (e) {
        print('Error initializing ViewModels: $e');
        _showErrorSnackBar('Error initializing booking. Please try again.');
      }
    });
  }

  @override
  void dispose() {
    try {
      if (!widget.isCompounderMode) {
        _razorpay.clear();
      }
    } catch (e) {
      print('Error disposing Razorpay: $e');
    }
    super.dispose();
  }

  Future<void> _createAppointmentDocument({
    required BookingSlot slot,
    required DateTime selectedDate,
    required String timeRange,
    required String patientName,
    required String patientToken,
    required String ownerUserId,
  }) async {
    final formattedDate = DateFormat('yyyy-MM-dd').format(selectedDate);

    // Use transaction with retry to handle concurrent bookings
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      // CRITICAL: Check if seat is already booked BEFORE creating appointment
      // This prevents double-booking when multiple users click the same seat simultaneously
      // Query for existing appointments with same date, time, and seat number
      final conflictQuery = FirebaseFirestore.instance
          .collection('appointments')
          .where('appointmentDate', isEqualTo: formattedDate)
          .where('appointmentTime', isEqualTo: timeRange)
          .where('seatNumber', isEqualTo: slot.seatNumber)
          .where('status',
              whereIn: ['pending', 'in_progress', 'confirmed', 'completed']);

      // Get the query snapshot within transaction
      final conflictSnapshot = await conflictQuery.get();

      // If seat is already booked, throw error to abort transaction
      if (conflictSnapshot.docs.isNotEmpty) {
        throw Exception(
            'Seat ${slot.seatNumber} is already booked for this time slot. Please select another seat.');
      }

      // Seat is available - create appointment atomically
      final appointmentRef =
          FirebaseFirestore.instance.collection('appointments').doc();

      transaction.set(appointmentRef, {
        'patientId': ownerUserId, // owner (logged-in user)
        'patientToken': patientToken, // actual patient token id
        'patientName': patientName,
        'seatNumber': slot.seatNumber,
        'appointmentDate': formattedDate,
        'appointmentTime': timeRange,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
    });

    await _bookingViewModel.bookSlot(slot.seatNumber);
    await _bookingViewModel.loadBookedSlotsForDateAndTime(selectedDate,
        _pendingTimeSlotKey ?? _bookingViewModel.selectedTimeSlot!);

    // Send WhatsApp notification to doctor
    await WhatsAppService.sendBookingNotification(
      patientName: patientName,
      patientToken: patientToken,
      seatNumber: slot.seatNumber,
      appointmentDate: formattedDate,
      appointmentTime: timeRange,
    );
  }

  void _handlePaymentSuccess(PaymentSuccessResponse response) async {
    if (!mounted) return;

    setState(() {
      _isProcessingPayment = true;
    });

    try {
      final slot = _pendingSlot ?? _bookingViewModel.selectedSlot;
      final selectedDate = _pendingDate ?? _bookingViewModel.selectedDate;
      final selectedTimeSlot =
          _pendingTimeSlotKey ?? _bookingViewModel.selectedTimeSlot;
      final authViewModel = Provider.of<AuthViewModel>(context, listen: false);
      final owner = authViewModel.currentUser;

      if (slot == null ||
          selectedDate == null ||
          selectedTimeSlot == null ||
          owner == null) {
        _showErrorSnackBar('Booking data incomplete. Please try again.');
        return;
      }

      final timeRange = _bookingViewModel.getTimeSlotRange(selectedTimeSlot);

      String patientToken;
      String patientName;

      if (_pendingExistingTokenId != null) {
        // Existing patient: update lastVisited
        await _db.updatePatientLastVisited(_pendingExistingTokenId!);
        final record = await _db.getPatientByToken(_pendingExistingTokenId!);
        if (record == null) {
          throw Exception('Patient record not found after payment');
        }
        patientToken = record.tokenId;
        patientName = record.name;
      } else if (_pendingNewPatientData != null) {
        // Create new patient and get token
        patientToken = await _db.createPatientAfterPayment(
          name: _pendingNewPatientData!['name'] as String,
          mobileNumber: _pendingNewPatientData!['mobile'] as String,
          age: _pendingNewPatientData!['age'] as int,
          aadhaarLast4: _pendingNewPatientData!['aadhaarLast4'] as String,
          sex: _pendingNewPatientData!['sex'] as String?,
          weightKg: _pendingNewPatientData!['weightKg'] as int?,
          userPhoneNumber: Provider.of<AuthViewModel>(context, listen: false)
              .currentUser
              ?.phoneNumber,
        );
        patientName = _pendingNewPatientData!['name'] as String;
      } else {
        throw Exception('No patient context for payment');
      }

      await _createAppointmentDocument(
        slot: slot,
        selectedDate: selectedDate,
        timeRange: timeRange,
        patientName: patientName,
        patientToken: patientToken,
        ownerUserId: owner.uid,
      );

      if (mounted) {
        _showSuccessSnackBar(
            'Appointment confirmed for ${DateFormat('yyyy-MM-dd').format(selectedDate)} at $timeRange (Seat ${slot.seatNumber})');
        Navigator.pop(context, true);
      }
    } catch (e) {
      LoggingService.error(
          'Error processing appointment', e, StackTrace.current);
      if (mounted) {
        // Check if error is about seat already booked
        final errorMessage = e.toString().toLowerCase();
        if (errorMessage.contains('already booked') ||
            errorMessage.contains('seat')) {
          _showErrorSnackBar(
              'This seat was just booked by another user. Please select a different seat.');
        } else {
          _showErrorSnackBar(
              'Error processing appointment: ${e.toString()}. Please contact support if payment was deducted.');
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingPayment = false;
          _pendingExistingTokenId = null;
          _pendingNewPatientData = null;
          _pendingSlot = null;
          _pendingDate = null;
          _pendingTimeSlotKey = null;
        });
      }
    }
  }

  bool _validateBookingData(
      BookingSlot? slot, DateTime? date, String? timeSlot, dynamic user) {
    return slot != null && date != null && timeSlot != null && user != null;
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    if (!mounted) return;
    print('Payment error: ${response.code} - ${response.message}');
    _showErrorSnackBar(
        'Payment Failed: ${response.message ?? 'Unknown error'}');
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    if (!mounted) return;
    _showInfoSnackBar('External Wallet Selected: ${response.walletName}');
  }

  Future<void> _preBookingFlow(BookingSlot slot) async {
    final user = _authViewModel.currentUser;
    if (user == null) {
      _showErrorSnackBar('Please login to continue');
      return;
    }

    final selectedDate = _bookingViewModel.selectedDate;
    final selectedTimeSlot = _bookingViewModel.selectedTimeSlot;
    if (selectedDate == null || selectedTimeSlot == null) {
      _showErrorSnackBar('Please select date and time slot first');
      return;
    }

    // Ask if the patient has a token
    final hasToken = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Patient Identification'),
        content: const Text('Do you have a patient token ID?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );

    if (hasToken == true) {
      // Input token
      final tokenController = TextEditingController();
      final tokenId = await showDialog<String?>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Enter Patient Token ID'),
          content: TextField(
            controller: tokenController,
            decoration: const InputDecoration(
              labelText: 'Token ID',
              hintText: 'e.g., PAT000123',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () =>
                  Navigator.pop(context, tokenController.text.trim()),
              child: const Text('Continue'),
            ),
          ],
        ),
      );

      if (tokenId == null || tokenId.isEmpty) return;

      final record = await _db.getPatientByToken(tokenId);
      if (record == null) {
        _showErrorSnackBar('Invalid token. Please try again.');
        return;
      }

      final isValid = await _db.isFeeValidWithinDays(record, days: 7);
      // In compounder mode, always ask for payment method and log, even if fee is valid
      if (widget.isCompounderMode || !isValid) {
        _pendingExistingTokenId = tokenId;
        _pendingNewPatientData = null;
        _pendingSlot = slot;
        _pendingDate = selectedDate;
        _pendingTimeSlotKey = selectedTimeSlot;
        await _initiatePayment(slot, patientNameOverride: record.name);
        return;
      }
      // Non-compounder and valid within days: skip payment
      try {
        await _createAppointmentDocument(
          slot: slot,
          selectedDate: selectedDate,
          timeRange: _bookingViewModel.getTimeSlotRange(selectedTimeSlot),
          patientName: record.name,
          patientToken: record.tokenId,
          ownerUserId: user.uid,
        );
        if (mounted) {
          _showSuccessSnackBar(
              'Appointment confirmed without payment (valid within 7 days).');
          Navigator.pop(context, true);
        }
      } catch (e) {
        _showErrorSnackBar('Failed to confirm appointment: $e');
      }
      return;
    } else {
      // New patient registration fields
      final nameCtrl = TextEditingController();
      final mobileCtrl = TextEditingController();
      final ageCtrl = TextEditingController();
      final aadhaarCtrl = TextEditingController();
      final weightCtrl = TextEditingController();
      String sexValue = 'M';

      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('New Patient Details'),
          content: StatefulBuilder(
            builder: (context, setStateDialog) {
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: 'Full Name'),
                    ),
                    TextField(
                      controller: mobileCtrl,
                      decoration:
                          const InputDecoration(labelText: 'Mobile Number'),
                      keyboardType: TextInputType.phone,
                    ),
                    TextField(
                      controller: ageCtrl,
                      decoration: const InputDecoration(labelText: 'Age'),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 8),
                    // Sex selection with simple M/F chips
                    Row(
                      children: [
                        const Text('Sex:'),
                        const SizedBox(width: 12),
                        Wrap(
                          spacing: 8,
                          children: [
                            ChoiceChip(
                              label: const Text('M'),
                              selected: sexValue == 'M',
                              onSelected: (sel) {
                                if (sel) {
                                  setStateDialog(() {
                                    sexValue = 'M';
                                  });
                                }
                              },
                            ),
                            ChoiceChip(
                              label: const Text('F'),
                              selected: sexValue == 'F',
                              onSelected: (sel) {
                                if (sel) {
                                  setStateDialog(() {
                                    sexValue = 'F';
                                  });
                                }
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                    TextField(
                      controller: weightCtrl,
                      decoration:
                          const InputDecoration(labelText: 'Weight (kg)'),
                      keyboardType: TextInputType.number,
                    ),
                    TextField(
                      controller: aadhaarCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Aadhaar last 4 digits'),
                      maxLength: 4,
                      keyboardType: TextInputType.number,
                    ),
                  ],
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Proceed to Pay'),
            ),
          ],
        ),
      );

      if (proceed != true) return;

      final age = int.tryParse(ageCtrl.text.trim()) ?? 0;
      final weight = int.tryParse(weightCtrl.text.trim());
      final aadhaarLast4 = aadhaarCtrl.text.trim();
      if (nameCtrl.text.trim().isEmpty ||
          mobileCtrl.text.trim().isEmpty ||
          age <= 0 ||
          aadhaarLast4.length != 4) {
        _showErrorSnackBar('Please fill all fields correctly.');
        return;
      }

      // Check token ID limit before proceeding
      final authViewModel = Provider.of<AuthViewModel>(context, listen: false);
      final userPhone = authViewModel.currentUser?.phoneNumber;
      if (userPhone != null && userPhone.isNotEmpty) {
        try {
          final tokenCount = await _db.getTokenIdCountForUser(userPhone);
          if (tokenCount >= 7) {
            _showErrorSnackBar(
                'Maximum limit reached! You can create only 7 token IDs per phone number. Please use an existing token ID or contact support.');
            return;
          }
          // Show warning if approaching limit
          if (tokenCount >= 5) {
            _showWarningSnackBar(
                'Warning: You have $tokenCount/7 token IDs. You can create ${7 - tokenCount} more.');
          }
        } catch (e) {
          _showErrorSnackBar('Error checking token limit: $e');
          return;
        }
      }

      _pendingExistingTokenId = null;
      _pendingNewPatientData = {
        'name': nameCtrl.text.trim(),
        'mobile': mobileCtrl.text.trim(),
        'age': age,
        'aadhaarLast4': aadhaarLast4,
        // Map 'M'/'F' chips to 'male'/'female' strings
        'sex': sexValue == 'M' ? 'male' : 'female',
        'weightKg': weight,
      };
      _pendingSlot = slot;
      _pendingDate = selectedDate;
      _pendingTimeSlotKey = selectedTimeSlot;
      await _initiatePayment(slot, patientNameOverride: nameCtrl.text.trim());
      return;
    }
  }

  Future<void> _initiatePayment(BookingSlot slot,
      {required String patientNameOverride}) async {
    if (_isProcessingPayment) return;

    final authViewModel = Provider.of<AuthViewModel>(context, listen: false);
    final user = authViewModel.currentUser;

    // Validate user authentication
    if (user == null) {
      _showErrorSnackBar('Please login to continue');
      return;
    }

    // Validate slot availability
    if (slot.isDisabled || !slot.canBook()) {
      _showErrorSnackBar('This slot is no longer available');
      return;
    }

    if (widget.isCompounderMode) {
      // Manual payment: Ask Cash/Online, then process success flow and log compunder_pay
      final method = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Select Payment Method'),
          content: const Text('Choose how the patient paid'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, 'cash'),
                child: const Text('Cash')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, 'online'),
                child: const Text('Online')),
          ],
        ),
      );
      if (method == null) return;
      await _handleManualPaymentSuccess(method);
      return;
    } else {
      _showInfoSnackBar('Initializing payment...');
      try {
        final options = _buildPaymentOptions(slot, user, patientNameOverride);
        _razorpay.open(options);
      } catch (e) {
        print('Payment initiation error: $e');
        _showErrorSnackBar('Failed to initialize payment. Please try again.');
      }
    }
  }

  Future<void> _handleManualPaymentSuccess(String method) async {
    if (!mounted) return;
    setState(() {
      _isProcessingPayment = true;
    });

    try {
      final slot = _pendingSlot ?? _bookingViewModel.selectedSlot;
      final selectedDate = _pendingDate ?? _bookingViewModel.selectedDate;
      final selectedTimeSlot =
          _pendingTimeSlotKey ?? _bookingViewModel.selectedTimeSlot;

      if (slot == null || selectedDate == null || selectedTimeSlot == null) {
        _showErrorSnackBar('Booking data incomplete. Please try again.');
        return;
      }

      final timeRange = _bookingViewModel.getTimeSlotRange(selectedTimeSlot);
      String patientToken;
      String patientName;
      String mobile = '';
      int age = 0;

      if (_pendingExistingTokenId != null) {
        await _db.updatePatientLastVisited(_pendingExistingTokenId!);
        final record = await _db.getPatientByToken(_pendingExistingTokenId!);
        if (record == null) {
          throw Exception('Patient record not found after payment');
        }
        patientToken = record.tokenId;
        patientName = record.name;
        mobile = record.mobileNumber;
      } else if (_pendingNewPatientData != null) {
        patientToken = await _db.createPatientAfterPayment(
          name: _pendingNewPatientData!['name'] as String,
          mobileNumber: _pendingNewPatientData!['mobile'] as String,
          age: _pendingNewPatientData!['age'] as int,
          aadhaarLast4: _pendingNewPatientData!['aadhaarLast4'] as String,
          sex: _pendingNewPatientData!['sex'] as String?,
          weightKg: _pendingNewPatientData!['weightKg'] as int?,
          userPhoneNumber: Provider.of<AuthViewModel>(context, listen: false)
              .currentUser
              ?.phoneNumber,
        );
        patientName = _pendingNewPatientData!['name'] as String;
        mobile = _pendingNewPatientData!['mobile'] as String;
        age = _pendingNewPatientData!['age'] as int;
      } else {
        throw Exception('No patient context for payment');
      }

      // Create appointment with a compounder ownerId marker
      await _createAppointmentDocument(
        slot: slot,
        selectedDate: selectedDate,
        timeRange: timeRange,
        patientName: patientName,
        patientToken: patientToken,
        ownerUserId: 'compounder_action',
      );

      // Log into compunder_pay
      await _compounderPaymentService.addPaymentRecord(
        patientToken: patientToken,
        patientName: patientName,
        mobileNumber: mobile,
        age: age,
        method: method,
      );

      if (mounted) {
        _showSuccessSnackBar(
            'Appointment confirmed for ${DateFormat('yyyy-MM-dd').format(selectedDate)} at $timeRange (Seat ${slot.seatNumber})');
        Navigator.pop(context, true);
      }
    } catch (e) {
      print('Error processing appointment (manual): $e');
      if (mounted) {
        _showErrorSnackBar('Error processing appointment.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingPayment = false;
          _pendingExistingTokenId = null;
          _pendingNewPatientData = null;
          _pendingSlot = null;
          _pendingDate = null;
          _pendingTimeSlotKey = null;
        });
      }
    }
  }

  Map<String, dynamic> _buildPaymentOptions(
      BookingSlot slot, dynamic user, String patientName) {
    return {
      'key': 'rzp_test_Kt8jSnWJ7nCCwX',
      'amount': 30000,
      'name': 'Doctor Appointment',
      'description': 'Booking for Seat ${slot.seatNumber} - $patientName',
      'timeout': 300,
      'prefill': {
        'contact': user.phoneNumber,
        'email': user.email,
      },
      'theme': {'color': '#528ff0'}
    };
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showWarningSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showInfoSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Consumer2<BookingViewModel, AuthViewModel>(
      builder: (context, bookingViewModel, authViewModel, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Book Appointment'),
            elevation: 2,
          ),
          body: Stack(
            children: [
              Column(
                children: [
                  _buildDateSelection(context, bookingViewModel),
                  if (bookingViewModel.selectedDate != null)
                    _buildTimeSlotSelection(context, bookingViewModel),
                  if (bookingViewModel.selectedDate != null &&
                      bookingViewModel.selectedTimeSlot != null)
                    _buildSeatGrid(context, bookingViewModel),
                ],
              ),
              if (_isProcessingPayment)
                Container(
                  color: Colors.black54,
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Colors.white),
                        SizedBox(height: 16),
                        Text(
                          'Processing your appointment...',
                          style: TextStyle(color: Colors.white, fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDateSelection(
      BuildContext context, BookingViewModel bookingViewModel) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Select Date:',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 50,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: bookingViewModel.availableDates.length,
              itemBuilder: (context, index) {
                final date = bookingViewModel.availableDates[index];
                final isSelected = bookingViewModel.selectedDate != null &&
                    bookingViewModel.selectedDate!.year == date.year &&
                    bookingViewModel.selectedDate!.month == date.month &&
                    bookingViewModel.selectedDate!.day == date.day;

                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          isSelected ? Colors.green : Colors.grey.shade200,
                      foregroundColor:
                          isSelected ? Colors.white : Colors.black87,
                      elevation: isSelected ? 3 : 1,
                    ),
                    onPressed: () => bookingViewModel.selectDate(date),
                    child: Text(
                      DateFormat('MMM d').format(date),
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeSlotSelection(
      BuildContext context, BookingViewModel bookingViewModel) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Select Time Slot:',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildTimeSlotButton(context, bookingViewModel, 'morning'),
              _buildTimeSlotButton(context, bookingViewModel, 'afternoon'),
              _buildTimeSlotButton(context, bookingViewModel, 'evening'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimeSlotButton(
      BuildContext context, BookingViewModel viewModel, String timeSlot) {
    final isSelected = viewModel.selectedTimeSlot == timeSlot;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: isSelected ? Colors.green : Colors.grey.shade200,
            foregroundColor: isSelected ? Colors.white : Colors.black87,
            padding: const EdgeInsets.symmetric(vertical: 12),
            elevation: isSelected ? 3 : 1,
          ),
          onPressed: () => viewModel.setSelectedTimeSlot(timeSlot),
          child: Text(
            timeSlot.toUpperCase(),
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ),
      ),
    );
  }

  Widget _buildSeatGrid(
      BuildContext context, BookingViewModel bookingViewModel) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Select Seat:',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              bookingViewModel
                  .getTimeSlotRange(bookingViewModel.selectedTimeSlot!),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.grey.shade600,
                  ),
            ),
            const SizedBox(height: 16),
            _buildSeatLegend(),
            const SizedBox(height: 16),
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 10,
                  childAspectRatio: 1,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: bookingViewModel.slots.length,
                itemBuilder: (context, index) {
                  final slot = bookingViewModel.slots[index];
                  return _buildSeatButton(context, slot, bookingViewModel);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeatLegend() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildLegendItem('Available', Colors.blue),
        _buildLegendItem('Selected', Colors.green),
        _buildLegendItem('Booked', Colors.grey),
      ],
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildSeatButton(
      BuildContext context, BookingSlot slot, BookingViewModel viewModel) {
    final isBooked = slot.isDisabled ||
        !slot.canBook() ||
        viewModel.isSeatBooked(slot.seatNumber);
    final isSelected = viewModel.selectedSlot?.seatNumber == slot.seatNumber;

    return Tooltip(
      message: isBooked
          ? 'Seat ${slot.seatNumber} - Booked'
          : 'Seat ${slot.seatNumber} - Available',
      child: InkWell(
        onTap: isBooked ? null : () => _preBookingFlow(slot),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
            color: isBooked
                ? Colors.grey.shade400
                : isSelected
                    ? Colors.green
                    : Colors.blue,
            borderRadius: BorderRadius.circular(8),
            border: isBooked
                ? Border.all(color: Colors.grey.shade600, width: 1)
                : null,
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.green.withOpacity(0.3),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : isBooked
                    ? [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.2),
                          blurRadius: 2,
                          offset: const Offset(0, 1),
                        ),
                      ]
                    : null,
          ),
          child: Stack(
            children: [
              Center(
                child: Text(
                  '${slot.seatNumber}',
                  style: TextStyle(
                    color: isBooked ? Colors.grey.shade700 : Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              if (isBooked)
                Positioned(
                  top: 2,
                  right: 2,
                  child: Icon(
                    Icons.block,
                    size: 10,
                    color: Colors.grey.shade600,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
