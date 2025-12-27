import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../viewmodels/booking_view_model.dart';
import '../../viewmodels/compounder_booking_view_model.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../services/database_service.dart';
import '../../utils/locator.dart';

class CompounderBookingScreen extends StatefulWidget {
  const CompounderBookingScreen({super.key});

  @override
  State<CompounderBookingScreen> createState() =>
      _CompounderBookingScreenState();
}

class _CompounderBookingScreenState extends State<CompounderBookingScreen> {
  String? _selectedDateKey;
  String? _selectedTimeSlot;
  int? _selectedSeat;

  final TextEditingController _tokenController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _mobileController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _aadhaarLast4Controller = TextEditingController();

  final DatabaseService _db = locator<DatabaseService>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Default date to today
      final nowKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
      setState(() => _selectedDateKey = nowKey);
      context.read<BookingViewModel>().selectDate(DateTime.parse(nowKey));
    });
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _nameController.dispose();
    _mobileController.dispose();
    _ageController.dispose();
    _aadhaarLast4Controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selectedDateKey == null ||
        _selectedTimeSlot == null ||
        _selectedSeat == null) {
      _snack('Select date, time slot and seat', Colors.orange);
      return;
    }

    final bookingVm = context.read<BookingViewModel>();
    final compounderVm = context.read<CompounderBookingViewModel>();
    final date = DateTime.parse(_selectedDateKey!);
    final token = _tokenController.text.trim();

    // Check if token is valid (within 5 days) to skip payment
    bool skipPayment = false;
    if (token.isNotEmpty) {
      final record = await _db.getPatientByToken(token);
      if (record == null) {
        _snack('Invalid token ID', Colors.red);
        return;
      }
      // Check validity: 5 days means day 1 to day 5 (booking date + 4 days)
      // Use booking date instead of today - if booking for tomorrow, check validity on tomorrow
      final isValid = await _db.isFeeValidWithinDays(
        record,
        days: 5,
        referenceDate: date,
      );
      if (isValid) {
        skipPayment = true;
      }
    }

    // If payment needed (new patient or fee expired), ask for payment method
    String? method;
    if (!skipPayment) {
      method = await showDialog<String>(
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
    }

    bookingVm.selectDate(date);
    bookingVm.setSelectedTimeSlot(_selectedTimeSlot!);
    bookingVm.setSelectedSlot(
      bookingVm.slots.firstWhere((s) => s.seatNumber == _selectedSeat!),
    );

    // Reserve seat (disables under the same DB as patient side)
    final reserved = await bookingVm.bookSlot(_selectedSeat!);
    if (!reserved) {
      _snack('Seat not available anymore. Pick another.', Colors.red);
      return;
    }

    // Existing or new patient flow
    try {
      if (token.isNotEmpty) {
        if (skipPayment) {
          // Direct booking without payment (fee valid within 5 days)
          await compounderVm.bookForExistingTokenWithoutPayment(
            tokenId: token,
            patientNameFallback: _nameController.text.trim(),
            mobileFallback: _mobileController.text.trim(),
            seatNumber: _selectedSeat!,
            selectedDate: date,
            selectedTimeSlotKey: _selectedTimeSlot!,
          );
          _snack('Booked successfully (no payment - valid within 5 days)',
              Colors.green);
        } else {
          // Booking with payment (fee expired or new)
          await compounderVm.bookForExistingToken(
            tokenId: token,
            patientNameFallback: _nameController.text.trim(),
            mobileFallback: _mobileController.text.trim(),
            seatNumber: _selectedSeat!,
            selectedDate: date,
            selectedTimeSlotKey: _selectedTimeSlot!,
            method: method!,
          );
          _snack('Booked successfully ($method)', Colors.green);
        }
      } else {
        // New patient always requires payment
        final age = int.tryParse(_ageController.text.trim()) ?? 0;
        final aadhaar = _aadhaarLast4Controller.text.trim();
        if (_nameController.text.trim().isEmpty ||
            _mobileController.text.trim().isEmpty ||
            age <= 0 ||
            aadhaar.length != 4) {
          _snack('Please fill all details for new patient', Colors.red);
          return;
        }
        // Get user phone number for token limit check
        final authViewModel =
            Provider.of<AuthViewModel>(context, listen: false);
        final userPhone = authViewModel.currentUser?.phoneNumber;

        await compounderVm.bookForNewPatient(
          name: _nameController.text.trim(),
          mobile: _mobileController.text.trim(),
          age: age,
          aadhaarLast4: aadhaar,
          seatNumber: _selectedSeat!,
          selectedDate: date,
          selectedTimeSlotKey: _selectedTimeSlot!,
          method: method!,
          userPhoneNumber: userPhone,
        );
        _snack('Booked successfully ($method)', Colors.green);
      }
      _clear();
    } catch (e) {
      _snack('Error: $e', Colors.red);
    }
  }

  void _clear() {
    _tokenController.clear();
    _nameController.clear();
    _mobileController.clear();
    _ageController.clear();
    _aadhaarLast4Controller.clear();
    setState(() {
      _selectedSeat = null;
    });
  }

  void _snack(String m, Color c) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(m), backgroundColor: c));
  }

  @override
  Widget build(BuildContext context) {
    final compounderVm = context.watch<CompounderBookingViewModel>();
    return Scaffold(
      appBar: AppBar(title: const Text('Compounder Booking')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Consumer<BookingViewModel>(builder: (context, vm, _) {
              return Column(children: [
                Row(children: [
                  Expanded(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      hint: const Text('Select Date'),
                      value: _selectedDateKey,
                      items: vm.availableDates.map((d) {
                        final key = DateFormat('yyyy-MM-dd').format(d);
                        return DropdownMenuItem<String>(
                            value: key, child: Text(key));
                      }).toList(),
                      onChanged: (key) async {
                        setState(() => _selectedDateKey = key);
                        if (key != null) {
                          vm.selectDate(DateTime.parse(key));
                          if (_selectedTimeSlot != null) {
                            await vm.loadBookedSlotsForDateAndTime(
                                DateTime.parse(key), _selectedTimeSlot!);
                          }
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      hint: const Text('Time Slot'),
                      value: _selectedTimeSlot,
                      items: const [
                        DropdownMenuItem(
                            value: 'morning', child: Text('Morning')),
                        DropdownMenuItem(
                            value: 'afternoon', child: Text('Afternoon')),
                        DropdownMenuItem(
                            value: 'evening', child: Text('Evening')),
                      ],
                      onChanged: (val) async {
                        setState(() => _selectedTimeSlot = val);
                        if (_selectedDateKey != null && val != null) {
                          await vm.loadBookedSlotsForDateAndTime(
                              DateTime.parse(_selectedDateKey!), val);
                        }
                      },
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: vm.slots.map((slot) {
                    final isSelected = _selectedSeat == slot.seatNumber;
                    return ChoiceChip(
                      label: Text('${slot.seatNumber}'),
                      selected: isSelected,
                      onSelected: slot.isDisabled
                          ? null
                          : (sel) =>
                              setState(() => _selectedSeat = slot.seatNumber),
                    );
                  }).toList(),
                ),
              ]);
            }),
            const Divider(height: 24),
            Text('Patient Details',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _tokenController,
              decoration: const InputDecoration(
                  labelText: 'Existing Token ID (optional if new patient)'),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(labelText: 'Name'))),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _mobileController,
                  decoration: const InputDecoration(labelText: 'Mobile Number'),
                  keyboardType: TextInputType.phone,
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _ageController,
                  decoration: const InputDecoration(labelText: 'Age'),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _aadhaarLast4Controller,
                  decoration:
                      const InputDecoration(labelText: 'Aadhaar Last 4'),
                  maxLength: 4,
                  keyboardType: TextInputType.number,
                ),
              ),
            ]),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: compounderVm.isProcessing ? null : _submit,
                icon: const Icon(Icons.check_circle_outline),
                label: Text(compounderVm.isProcessing
                    ? 'Processing...'
                    : 'Book & Log Pay'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
