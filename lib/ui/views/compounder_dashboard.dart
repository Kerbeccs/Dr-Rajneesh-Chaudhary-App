import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../viewmodels/booking_view_model.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../services/compounder_payment_service.dart';
import 'booking_screen.dart';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:share_plus/share_plus.dart';

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

  String? _selectedDateKey; // 'yyyy-MM-dd'
  String? _selectedTimeSlot; // morning/afternoon/evening
  int? _selectedSeat;
  bool _isSubmitting = false;

  late BookingViewModel _bookingViewModel;
  final CompounderPaymentService _paymentService = CompounderPaymentService();

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

    // Choose pay method
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
          // Update lastVisited
          await FirebaseFirestore.instance
              .collection('patients')
              .doc(tokenId)
              .set({
            'lastVisited': DateTime.now().toIso8601String(),
            'updatedAt': DateTime.now().toIso8601String(),
          }, SetOptions(merge: true));
        }
      } else {
        // New patient: create token
        final counters =
            FirebaseFirestore.instance.collection('meta').doc('counters');
        final token =
            await FirebaseFirestore.instance.runTransaction((txn) async {
          final counterSnap = await txn.get(counters);
          int next = 1;
          if (counterSnap.exists) {
            final data = counterSnap.data() as Map<String, dynamic>;
            next = (data['patientCounter'] ?? 0) + 1;
          }
          txn.set(counters, {'patientCounter': next}, SetOptions(merge: true));
          return 'PAT${next.toString().padLeft(6, '0')}';
        });
        tokenId = token;
        await FirebaseFirestore.instance
            .collection('patients')
            .doc(tokenId)
            .set({
          'tokenId': tokenId,
          'name': patientName,
          'mobileNumber': mobile,
          'age': age,
          'aadhaarLast4': aadhaar4,
          'createdAt': DateTime.now().toIso8601String(),
          'lastVisited': DateTime.now().toIso8601String(),
          'updatedAt': DateTime.now().toIso8601String(),
        });
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

      // Log payment to compounder_pay
      await _paymentService.addPaymentRecord(
        patientToken: tokenId,
        patientName: patientName,
        mobileNumber: mobile,
        age: age,
        method: method,
      );

      _showSnack('Booked and logged payment ($method)', Colors.green);
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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _printAppointmentCard(Map<String, dynamic> appt) async {
    try {
      final tokenId = appt['patientToken'] as String?;
      if (tokenId == null || tokenId.isEmpty) {
        _showSnack('Missing token id');
        return;
      }

      // 1) Load patient details by tokenId from 'patients'
      final patSnap = await FirebaseFirestore.instance
          .collection('patients')
          .where('tokenId', isEqualTo: tokenId)
          .limit(1)
          .get();
      if (patSnap.docs.isEmpty) {
        _showSnack('Patient record not found');
        return;
      }
      final p = patSnap.docs.first.data();

      final name = (p['name'] ?? '').toString();
      final age = (p['age'] ?? '').toString();
      final weight = (p['weightKg'] ?? '').toString();
      final sex = (p['sex'] ?? '').toString();
      final phone = (p['mobileNumber'] ?? '').toString();
      final token = (p['tokenId'] ?? '').toString();
      final aadhaar = (p['aadhaarLast4'] ?? '').toString();

      // 2) Load base image from assets
      final byteData = await rootBundle.load('assets/logos/parcha.jpg');
      final Uint8List bytes = byteData.buffer.asUint8List();
      final ui.Codec codec = await ui.instantiateImageCodec(bytes);
      final ui.FrameInfo frame = await codec.getNextFrame();
      final ui.Image baseImage = frame.image;

      // 3) Draw text onto the image
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final ui.Canvas canvas = ui.Canvas(recorder);
      final paint = ui.Paint();
      // Draw the base image first
      canvas.drawImage(baseImage, const ui.Offset(0, 0), paint);

      textPainter(String text, double x, double y,
          {double fontSize = 28, ui.Color color = const ui.Color(0xFF000000)}) {
        final ui.ParagraphBuilder builder = ui.ParagraphBuilder(
          ui.ParagraphStyle(
            textAlign: TextAlign.left,
            fontSize: fontSize,
            maxLines: 1,
          ),
        )
          ..pushStyle(ui.TextStyle(color: color))
          ..addText(text);
        final ui.Paragraph paragraph = builder.build()
          ..layout(const ui.ParagraphConstraints(width: double.infinity));
        canvas.drawParagraph(paragraph, ui.Offset(x, y));
      }

      // Positioning: tweak Y values to align nicely on your parcha
      double startY = 80; // top padding
      const double startX = 40; // left padding
      const double gapY = 44; // vertical gap between lines

      // Shift content down by 5 lines
      startY += gapY * 7;

      textPainter('Token: $token', startX, startY);
      startY += gapY;
      textPainter('Name: $name', startX, startY);
      startY += gapY;
      textPainter('Age: $age', startX, startY);
      startY += gapY;
      textPainter('Weight: $weight', startX, startY);
      startY += gapY;
      textPainter('Sex: $sex', startX, startY);
      startY += gapY;
      textPainter('Aadhaar: $aadhaar', startX, startY);
      startY += gapY;
      textPainter('Phone: $phone', startX, startY);

      final ui.Picture picture = recorder.endRecording();
      final ui.Image finalImage = await picture.toImage(
        baseImage.width,
        baseImage.height,
      );
      final ByteData? pngBytes =
          await finalImage.toByteData(format: ui.ImageByteFormat.png);
      if (pngBytes == null) {
        _showSnack('Failed to compose image');
        return;
      }

      // 4) Save to temporary file
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/parcha_$token.png');
      await file.writeAsBytes(pngBytes.buffer.asUint8List(), flush: true);

      // 5) Share
      await Share.shareXFiles([XFile(file.path)], text: 'Patient Details');
    } catch (e) {
      _showSnack('Print failed: $e');
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Stream<List<Map<String, dynamic>>> _todayAppointmentsStream() {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    // OrderBy requires an index when combined with where; if index missing, fallback to simple fetch
    final col = FirebaseFirestore.instance.collection('appointments');
    return col
        .where('appointmentDate', isEqualTo: today)
        .snapshots()
        .map((q) => q.docs.map((d) => d.data()).toList());
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
              Text('Today\'s Patients',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
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
                stream: _todayAppointmentsStream(),
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
                    return const Text('No patients found.');
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
                          child: const Icon(Icons.tag, color: Colors.blue),
                        ),
                        title: Text(e['patientToken'] ?? ''),
                        subtitle: Text(
                            '${e['patientName'] ?? ''} • Seat ${e['seatNumber'] ?? ''} • ${e['appointmentTime'] ?? ''}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.print, color: Colors.blue),
                          onPressed: () => _printAppointmentCard(e),
                          tooltip: 'Print Patient Details',
                        ),
                      );
                    },
                  );
                },
              )
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
          } else {
            Navigator.pushNamed(context, '/compounder_patients');
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
