import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../viewmodels/booking_view_model.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../services/compounder_payment_service.dart';
import '../../services/database_service.dart';
import '../../utils/locator.dart'; // Import DI locator
import '../../services/parcha_print_service.dart';
import 'booking_screen.dart';

class CompounderDashboard extends StatelessWidget {
  const CompounderDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final authViewModel = Provider.of<AuthViewModel>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Compounder Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await authViewModel.signOut();
              if (context.mounted) {
                Navigator.pushReplacementNamed(context, '/login');
              }
            },
          )
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Image.asset(
              'assets/logos/public-health.png',
              height: 180,
              width: double.infinity,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 8),
            const _CompounderMenuGrid(),
          ],
        ),
      ),
    );
  }
}

// 1) Booking widget similar to patient side but without Razorpay.
class _CompounderBookingCard extends StatefulWidget {
  const _CompounderBookingCard();
  @override
  State<_CompounderBookingCard> createState() => _CompounderBookingCardState();
}

class _CompounderBookingCardState extends State<_CompounderBookingCard> {
  final TextEditingController _tokenController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _mobileController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _aadhaarLast4Controller = TextEditingController();
  final TextEditingController _addressController = TextEditingController();

  String? _selectedDateKey; // 'yyyy-MM-dd'
  String? _selectedTimeSlot; // morning/afternoon/evening
  int? _selectedSeat;
  bool _isSubmitting = false;

  late BookingViewModel _bookingViewModel;
  // Use dependency injection to get shared CompounderPaymentService instance
  final CompounderPaymentService _paymentService =
      locator<CompounderPaymentService>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bookingViewModel = Provider.of<BookingViewModel>(context, listen: false);
      // Default to today (normalized)
      final now = DateTime.now();
      final key = DateFormat('yyyy-MM-dd').format(now);
      _selectedDateKey = key;
      _bookingViewModel.selectDate(DateTime.parse(key));
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _nameController.dispose();
    _mobileController.dispose();
    _ageController.dispose();
    _aadhaarLast4Controller.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _book() async {
    if (_isSubmitting) return;
    if (_selectedDateKey == null ||
        _selectedTimeSlot == null ||
        _selectedSeat == null) {
      _showSnack('Select date, time slot and seat', Colors.orange);
      return;
    }

    final vm = _bookingViewModel;
    final seat = _selectedSeat!;
    final timeSlot = _selectedTimeSlot!;
    final date = DateTime.parse(_selectedDateKey!);

    // Validate/prepare patient
    String tokenId = _tokenController.text.trim();
    String patientName = _nameController.text.trim();
    String mobile = _mobileController.text.trim();
    final int age = int.tryParse(_ageController.text.trim()) ?? 0;
    final String aadhaar4 = _aadhaarLast4Controller.text.trim();

    if (tokenId.isEmpty &&
        (patientName.isEmpty ||
            mobile.isEmpty ||
            age <= 0 ||
            aadhaar4.length != 4)) {
      _showSnack('Provide token or full new patient details', Colors.red);
      return;
    }

    // Validate mobile number for new patients - cannot be compounder's number
    if (tokenId.isEmpty && mobile.contains('1234567890')) {
      _showSnack(
          'Invalid mobile number. Please enter a valid patient mobile number.',
          Colors.red);
      return;
    }

    // Check if token is valid (within 5 days) to skip payment
    final db = locator<DatabaseService>();
    bool skipPayment = false;
    if (tokenId.isNotEmpty) {
      final record = await db.getPatientByToken(tokenId);
      if (record != null) {
        final isValid = await db.isFeeValidWithinDays(
          record,
          days: 5,
          referenceDate: date,
        );
        if (isValid) {
          skipPayment = true;
        }
      }
    }

    // Only ask for payment method if payment is needed
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

    setState(() => _isSubmitting = true);
    try {
      // Resolve patient token/name for booking and payment log
      if (tokenId.isNotEmpty) {
        // Existing patient: fetch to get name & mobile (optional, best effort)
        final snap = await FirebaseFirestore.instance
            .collection('patients')
            .where('tokenId', isEqualTo: tokenId)
            .limit(1)
            .get();
        if (snap.docs.isNotEmpty) {
          final data = snap.docs.first.data();
          patientName = data['name'] ?? patientName;
          mobile = data['mobileNumber'] ?? mobile;

          // Only update lastVisited if payment is required (not valid within 5 days)
          if (!skipPayment) {
            await db.updatePatientLastVisited(tokenId, appointmentDate: date);
          }
        }
      } else {
        // New patient: create token using database service (handles token limit check)
        final authViewModel =
            Provider.of<AuthViewModel>(context, listen: false);
        final userPhone = authViewModel.currentUser?.phoneNumber;

        // Use database service from DI container
        final db = locator<DatabaseService>();

        tokenId = await db.createPatientAfterPayment(
          name: patientName,
          mobileNumber: mobile,
          age: age,
          aadhaarLast4: aadhaar4,
          address: _addressController.text.trim(),
          userPhoneNumber: userPhone,
          appointmentDate: date,
        );
      }

      // Book the seat (disable it)
      vm.selectDate(date);
      vm.setSelectedTimeSlot(timeSlot);
      vm.setSelectedSlot(
        vm.slots.firstWhere((s) => s.seatNumber == seat),
      );
      await vm.bookSlot(seat);

      // Create appointment document similar to patient flow
      final formattedDate = _selectedDateKey!;
      final timeRange = vm.getTimeSlotRange(timeSlot);
      await FirebaseFirestore.instance.collection('appointments').add({
        'patientId': 'compounder_action',
        'patientToken': tokenId,
        'patientName': patientName,
        'seatNumber': seat,
        'appointmentDate': formattedDate,
        'appointmentTime': timeRange,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Log payment only if payment was required
      if (!skipPayment) {
        await _paymentService.addPaymentRecord(
          patientToken: tokenId,
          patientName: patientName,
          mobileNumber: mobile,
          age: age,
          method: method!,
        );
        _showSnack('Booked and logged payment ($method)', Colors.green);
      } else {
        _showSnack('Booked successfully (no payment - valid within 5 days)',
            Colors.green);
      }
      _clearInputs();
    } catch (e) {
      _showSnack('Error: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _clearInputs() {
    _tokenController.clear();
    _nameController.clear();
    _mobileController.clear();
    _ageController.clear();
    _aadhaarLast4Controller.clear();
    _addressController.clear();
    _selectedSeat = null;
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 4,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Book Appointment (Compounder)',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Consumer<BookingViewModel>(builder: (context, vm, _) {
                return Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            hint: const Text('Select Date'),
                            value: _selectedDateKey,
                            items: vm.availableDates.map((d) {
                              final key = DateFormat('yyyy-MM-dd').format(d);
                              return DropdownMenuItem<String>(
                                value: key,
                                child: Text(key),
                              );
                            }).toList(),
                            onChanged: (key) async {
                              if (key == null) return;
                              setState(() => _selectedDateKey = key);
                              vm.selectDate(DateTime.parse(key));
                              if (_selectedTimeSlot != null) {
                                await vm.loadBookedSlotsForDateAndTime(
                                    DateTime.parse(key), _selectedTimeSlot!);
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
                      ],
                    ),
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
                              : (sel) {
                                  setState(() {
                                    _selectedSeat = slot.seatNumber;
                                  });
                                },
                        );
                      }).toList(),
                    ),
                  ],
                );
              }),
              const Divider(height: 24),
              Text('Patient Details',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              TextField(
                controller: _tokenController,
                decoration: const InputDecoration(
                  labelText: 'Existing Token ID (optional if new patient)',
                ),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: 'Name'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _mobileController,
                    decoration:
                        const InputDecoration(labelText: 'Mobile Number'),
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
              const SizedBox(height: 8),
              TextField(
                controller: _addressController,
                decoration: const InputDecoration(
                    labelText: 'Address (max 30 characters)'),
                maxLength: 30,
                maxLines: 2,
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSubmitting ? null : _book,
                  icon: const Icon(Icons.check_circle_outline),
                  label:
                      Text(_isSubmitting ? 'Processing...' : 'Book & Log Pay'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 2) Today's patients list with search (read-only)
class _TodaysPatientsCard extends StatefulWidget {
  const _TodaysPatientsCard();
  @override
  State<_TodaysPatientsCard> createState() => _TodaysPatientsCardState();
}

class _TodaysPatientsCardState extends State<_TodaysPatientsCard> {
  final TextEditingController _searchController = TextEditingController();
  DateTime? _selectedDate;
  String? _selectedTimeSlot;

  @override
  void initState() {
    super.initState();
    // Default to today
    _selectedDate = DateTime.now();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<DateTime> get availableDates {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    return [today, tomorrow];
  }

  String getTimeSlotRange(String timeSlot) {
    switch (timeSlot) {
      case 'morning':
        return '9:30 AM - 2:30 PM';
      case 'afternoon':
        return '3:00 PM - 5:00 PM';
      case 'evening':
        return '5:30 PM - 8:00 PM';
      default:
        return '';
    }
  }

  Future<void> _printAppointmentCard(Map<String, dynamic> appt) async {
    await ParchaPrintService.printPatientCard(
      appointment: appt,
      onError: _showSnack,
    );
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Stream<List<Map<String, dynamic>>> _appointmentsStream() {
    if (_selectedDate == null || _selectedTimeSlot == null) {
      return Stream.value([]);
    }

    final formattedDate = DateFormat('yyyy-MM-dd').format(_selectedDate!);
    final timeRange = getTimeSlotRange(_selectedTimeSlot!);

    final col = FirebaseFirestore.instance.collection('appointments');
    return col
        .where('appointmentDate', isEqualTo: formattedDate)
        .where('appointmentTime', isEqualTo: timeRange)
        .where('status', whereIn: ['pending', 'in_progress'])
        .snapshots()
        .map((q) {
          final list = q.docs.map((d) => d.data()).toList();
          // Sort by seat number
          list.sort((a, b) {
            final seatA = a['seatNumber'] as int? ?? 0;
            final seatB = b['seatNumber'] as int? ?? 0;
            return seatA.compareTo(seatB);
          });
          return list;
        });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Patients List',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),

              // Date Selection
              Text('Select Date:',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: availableDates.map((date) {
                    final isSelected = _selectedDate != null &&
                        _selectedDate!.year == date.year &&
                        _selectedDate!.month == date.month &&
                        _selectedDate!.day == date.day;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isSelected ? Colors.green : null,
                        ),
                        onPressed: () {
                          setState(() {
                            _selectedDate = date;
                            _selectedTimeSlot = null; // Reset time slot
                          });
                        },
                        child: Text(DateFormat('MMM d').format(date)),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 16),

              // Time Slot Selection (only show if date is selected)
              if (_selectedDate != null) ...[
                Text('Select Time Slot:',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _selectedTimeSlot == 'morning'
                              ? Colors.blue
                              : null,
                        ),
                        onPressed: () {
                          setState(() {
                            _selectedTimeSlot = 'morning';
                          });
                        },
                        child: const Text('Morning\n9:30-2:30',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _selectedTimeSlot == 'afternoon'
                              ? Colors.blue
                              : null,
                        ),
                        onPressed: () {
                          setState(() {
                            _selectedTimeSlot = 'afternoon';
                          });
                        },
                        child: const Text('Afternoon\n3:00-5:00',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _selectedTimeSlot == 'evening'
                              ? Colors.blue
                              : null,
                        ),
                        onPressed: () {
                          setState(() {
                            _selectedTimeSlot = 'evening';
                          });
                        },
                        child: const Text('Evening\n5:30-8:00',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],

              // Search field and patient list (only show if time slot is selected)
              if (_selectedTimeSlot != null) ...[
                TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    labelText: 'Search by Token ID',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _appointmentsStream(),
                  builder: (context, snap) {
                    if (!snap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final list = snap.data ?? [];
                    final q = _searchController.text.trim().toLowerCase();
                    final filtered = q.isEmpty
                        ? list
                        : list
                            .where((e) => (e['patientToken'] ?? '')
                                .toString()
                                .toLowerCase()
                                .contains(q))
                            .toList();
                    if (filtered.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text('No patients found for this slot.'),
                      );
                    }
                    return ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 16),
                      itemBuilder: (context, idx) {
                        final e = filtered[idx];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.blue.shade100,
                            child: Text('${e['seatNumber'] ?? ''}',
                                style: const TextStyle(color: Colors.blue)),
                          ),
                          title: Text('Token: ${e['patientToken'] ?? ''}'),
                          subtitle: Text(
                              'Name: ${e['patientName'] ?? ''}\nSeat: ${e['seatNumber'] ?? ''} • Time: ${e['appointmentTime'] ?? ''}'),
                          isThreeLine: true,
                          trailing: IconButton(
                            icon: const Icon(Icons.print, color: Colors.blue),
                            onPressed: () => _printAppointmentCard(e),
                            tooltip: 'Print Patient Details',
                          ),
                        );
                      },
                    );
                  },
                ),
              ] else if (_selectedDate != null) ...[
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('Please select a time slot to view patients.',
                      style: TextStyle(color: Colors.grey)),
                ),
              ] else ...[
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('Please select a date to begin.',
                      style: TextStyle(color: Colors.grey)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// Menu grid with two widgets: Booking and Patients List
class _CompounderMenuGrid extends StatelessWidget {
  const _CompounderMenuGrid();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        mainAxisSpacing: 20,
        crossAxisSpacing: 20,
        children: [
          // Bookings → open patient UI booking in compounder mode (manual pay)
          Card(
            elevation: 4,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            child: InkWell(
              onTap: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const _CompounderPatientUiEntry(),
                ));
              },
              borderRadius: BorderRadius.circular(15),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Colors.teal.withOpacity(0.7), Colors.teal],
                  ),
                ),
                child: const Center(
                  child: Text(
                    'Bookings (Manual Pay)',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const _MenuCard(
            title: 'Today\'s Patients',
            icon: Icons.people_alt_outlined,
            color: Colors.indigo,
            routeKey: 'patients',
          ),
          const _MenuCard(
            title: 'Search Tokens',
            icon: Icons.search,
            color: Colors.orange,
            routeKey: 'search',
          ),
        ],
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final String routeKey; // 'booking' | 'patients'

  const _MenuCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.routeKey,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: InkWell(
        onTap: () {
          if (routeKey == 'booking') {
            Navigator.pushNamed(context, '/compounder_booking');
          } else if (routeKey == 'search') {
            // Open the Token Search screen
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const _TokenSearchScreen(),
            ));
          } else {
            // Open the Patients List screen
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const _PatientsListScreen(),
            ));
          }
        },
        borderRadius: BorderRadius.circular(15),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [color.withOpacity(0.7), color],
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 48, color: Colors.white),
              const SizedBox(height: 10),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Screen to display patients list
class _PatientsListScreen extends StatelessWidget {
  const _PatientsListScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Patients List'),
      ),
      body: const SingleChildScrollView(
        child: _TodaysPatientsCard(),
      ),
    );
  }
}

// Screen to search tokens by phone number
class _TokenSearchScreen extends StatefulWidget {
  const _TokenSearchScreen();

  @override
  State<_TokenSearchScreen> createState() => _TokenSearchScreenState();
}

class _TokenSearchScreenState extends State<_TokenSearchScreen> {
  final TextEditingController _phoneController = TextEditingController();
  List<Map<String, dynamic>> _tokens = [];
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  // Helper function to safely convert to Timestamp
  Timestamp? _toTimestamp(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value;
    if (value is String) {
      try {
        // Try to parse as DateTime first, then convert to Timestamp
        final dateTime = DateTime.parse(value);
        return Timestamp.fromDate(dateTime);
      } catch (e) {
        return null;
      }
    }
    return null;
  }

  Future<void> _searchTokens() async {
    final phoneNumber = _phoneController.text.trim();
    if (phoneNumber.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter a phone number';
        _tokens = [];
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _tokens = [];
    });

    try {
      // Search for tokens where patient's mobile number matches
      final mobileQuery = await FirebaseFirestore.instance
          .collection('patients')
          .where('mobileNumber', isEqualTo: phoneNumber)
          .get();

      // Search for tokens created by this user (userPhoneNumber)
      // Try with different phone formats
      final phoneVariants = {
        phoneNumber,
        '+91$phoneNumber',
        phoneNumber.startsWith('+91') ? phoneNumber.substring(3) : phoneNumber,
      }.toList();

      final userPhoneQuery = await FirebaseFirestore.instance
          .collection('patients')
          .where('userPhoneNumber', whereIn: phoneVariants)
          .get();

      // Combine results and remove duplicates
      final Map<String, Map<String, dynamic>> tokensMap = {};

      // Add mobile number matches
      for (var doc in mobileQuery.docs) {
        final data = doc.data();
        tokensMap[data['tokenId']] = {
          'tokenId': data['tokenId'] ?? '',
          'name': data['name'] ?? '',
          'age': data['age'] ?? '',
          'mobileNumber': data['mobileNumber'] ?? '',
          'aadhaarLast4': data['aadhaarLast4'] ?? '',
          'address': data['address'] ?? '',
          'userPhoneNumber': data['userPhoneNumber'] ?? '',
          'createdAt': data['createdAt'],
          'lastVisited': data['lastVisited'],
        };
      }

      // Add userPhoneNumber matches
      for (var doc in userPhoneQuery.docs) {
        final data = doc.data();
        tokensMap[data['tokenId']] = {
          'tokenId': data['tokenId'] ?? '',
          'name': data['name'] ?? '',
          'age': data['age'] ?? '',
          'mobileNumber': data['mobileNumber'] ?? '',
          'aadhaarLast4': data['aadhaarLast4'] ?? '',
          'address': data['address'] ?? '',
          'userPhoneNumber': data['userPhoneNumber'] ?? '',
          'createdAt': data['createdAt'],
          'lastVisited': data['lastVisited'],
        };
      }

      if (tokensMap.isEmpty) {
        setState(() {
          _errorMessage = 'No tokens found for this phone number';
          _tokens = [];
          _isLoading = false;
        });
        return;
      }

      // Convert to list and sort by creation date (newest first)
      final tokensList = tokensMap.values.toList();
      tokensList.sort((a, b) {
        final aTime = _toTimestamp(a['createdAt']);
        final bTime = _toTimestamp(b['createdAt']);
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime);
      });

      setState(() {
        _tokens = tokensList;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error searching: $e';
        _tokens = [];
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search Tokens by Phone'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Search field
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _phoneController,
                    decoration: const InputDecoration(
                      labelText: 'Search by Phone Number',
                      hintText: 'Patient or Creator phone',
                      helperText: 'Searches both patient & creator phone',
                      prefixIcon: Icon(Icons.phone),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.phone,
                    onSubmitted: (_) => _searchTokens(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isLoading ? null : _searchTokens,
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Results
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(color: Colors.red.shade700),
                ),
              ),

            if (_tokens.isNotEmpty) ...[
              Text(
                'Found ${_tokens.length} token(s)',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
            ],

            Expanded(
              child: _tokens.isEmpty
                  ? Center(
                      child: Text(
                        _isLoading
                            ? 'Searching...'
                            : 'Enter a phone number to search for tokens',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 16,
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _tokens.length,
                      separatorBuilder: (_, __) => const Divider(),
                      itemBuilder: (context, index) {
                        final token = _tokens[index];
                        final createdAt = _toTimestamp(token['createdAt']);
                        final lastVisited = _toTimestamp(token['lastVisited']);
                        final userPhone =
                            token['userPhoneNumber']?.toString() ?? '';

                        // Check if created by compounder (phone number 1234567890)
                        final isCompounderCreated =
                            userPhone.contains('1234567890');
                        final creatorDisplay = isCompounderCreated
                            ? 'Created by: Compounder'
                            : userPhone.isNotEmpty
                                ? 'Created by: $userPhone'
                                : 'Created by: Unknown';

                        return Card(
                          elevation: 2,
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: isCompounderCreated
                                  ? Colors.blue.shade100
                                  : Colors.orange.shade100,
                              child: Icon(
                                isCompounderCreated
                                    ? Icons.medical_services
                                    : Icons.tag,
                                color: isCompounderCreated
                                    ? Colors.blue
                                    : Colors.orange,
                              ),
                            ),
                            title: Text(
                              'Token: ${token['tokenId']}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Name: ${token['name']}'),
                                Text('Age: ${token['age']}'),
                                Text('Patient Phone: ${token['mobileNumber']}'),
                                if (token['aadhaarLast4'] != null &&
                                    token['aadhaarLast4'].toString().isNotEmpty)
                                  Text('Aadhaar: ${token['aadhaarLast4']}'),
                                if (token['address'] != null &&
                                    token['address'].toString().isNotEmpty)
                                  Text('Address: ${token['address']}'),
                                const SizedBox(height: 4),
                                Text(
                                  creatorDisplay,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isCompounderCreated
                                        ? Colors.blue.shade700
                                        : Colors.green.shade700,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (createdAt != null)
                                  Text(
                                    'Created: ${DateFormat('dd/MM/yyyy').format(createdAt.toDate())}',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600),
                                  ),
                                if (lastVisited != null)
                                  Text(
                                    'Last Visit: ${DateFormat('dd/MM/yyyy').format(lastVisited.toDate())}',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600),
                                  ),
                              ],
                            ),
                            isThreeLine: false,
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// Opens the same booking UI used by patients, but in compounder mode (manual pay)
class _CompounderPatientUiEntry extends StatelessWidget {
  const _CompounderPatientUiEntry();
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => BookingViewModel(),
      child: const _CompounderPatientUiPage(),
    );
  }
}

class _CompounderPatientUiPage extends StatelessWidget {
  const _CompounderPatientUiPage();
  @override
  Widget build(BuildContext context) {
    return const _BookingScreenCompounderWrapper();
  }
}

// Lightweight wrapper to instantiate booking screen in compounder mode
class _BookingScreenCompounderWrapper extends StatelessWidget {
  const _BookingScreenCompounderWrapper();
  @override
  Widget build(BuildContext context) {
    return const _BookingScreenCompounderScaffold();
  }
}

class _BookingScreenCompounderScaffold extends StatelessWidget {
  const _BookingScreenCompounderScaffold();
  @override
  Widget build(BuildContext context) {
    return const _BookingScreenCompounderContent();
  }
}

class _BookingScreenCompounderContent extends StatelessWidget {
  const _BookingScreenCompounderContent();
  @override
  Widget build(BuildContext context) {
    // Import locally to avoid a new top import
    return const BookingScreen(isCompounderMode: true);
  }
}
