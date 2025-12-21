import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../viewmodels/doctor_appointments_view_model.dart';
import '../widgets/appointment_card.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:share_plus/share_plus.dart';

class DoctorAppointmentsScreen extends StatefulWidget {
  const DoctorAppointmentsScreen({super.key});

  @override
  State<DoctorAppointmentsScreen> createState() =>
      _DoctorAppointmentsScreenState();
}

class _DoctorAppointmentsScreenState extends State<DoctorAppointmentsScreen>
    with WidgetsBindingObserver {
  DoctorAppointmentsViewModel? _viewModel;

  @override
  void initState() {
    super.initState();
    // Register for app lifecycle changes
    WidgetsBinding.instance.addObserver(this);
    // We use addPostFrameCallback to ensure context is available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return; // Check if widget is still mounted
      try {
        // Obtain the view model. listen: false because we manage updates manually.
        _viewModel =
            Provider.of<DoctorAppointmentsViewModel>(context, listen: false);
        // Add listener to trigger setState when ViewModel changes
        _viewModel?.addListener(_onViewModelChange);
        // Resume the view model when the screen becomes active
        _viewModel?.resume();
      } catch (e) {
        // Handle potential errors during view model initialization if necessary
        debugPrint('Error initializing ViewModel: $e');
        // Optionally set an error state in the screen if initialization fails
      }
    });
  }

  // Listener method that calls setState if the widget is mounted
  void _onViewModelChange() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    // Unregister from app lifecycle changes
    WidgetsBinding.instance.removeObserver(this);
    // Remove the listener
    _viewModel?.removeListener(_onViewModelChange);
    // Pause the view model when the screen is no longer active
    _viewModel?.pause();
    // Do NOT dispose the view model here as it's provided at a higher level
    // _viewModel?.dispose(); // REMOVED
    _viewModel = null; // Null out the reference
    super.dispose();
  }

  // Handle app lifecycle changes (background/foreground)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (_viewModel == null) return;

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        // App is going to background or becoming inactive
        debugPrint('App going to background - pausing timer');
        _viewModel?.pause();
        break;
      case AppLifecycleState.resumed:
        // App is coming back to foreground
        debugPrint('App coming to foreground - resuming if needed');
        // Only resume if the screen is still mounted and visible
        if (mounted) {
          _viewModel?.resume();
        }
        break;
      case AppLifecycleState.detached:
        // App is being terminated
        debugPrint('App being terminated - pausing timer');
        _viewModel?.pause();
        break;
      case AppLifecycleState.hidden:
        // App is hidden (iOS specific)
        debugPrint('App hidden - pausing timer');
        _viewModel?.pause();
        break;
    }
  }

  // Helper to safely perform asynchronous operations on the view model
  Future<void> _performViewModelOperation(
      Future<void> Function(DoctorAppointmentsViewModel vm) operation) async {
    // Check if the widget is mounted and the view model is available before executing the operation
    if (!mounted || _viewModel == null) {
      debugPrint(
          'Operation cancelled: Widget not mounted or ViewModel not available.');
      return;
    }
    try {
      await operation(_viewModel!); // Execute the operation
      // State update will be handled by the _onViewModelChange listener
    } catch (e) {
      debugPrint('Error during ViewModel operation: $e');
      // Optionally show an error message to the user
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show a loading indicator or error if the view model hasn't been initialized yet
    if (_viewModel == null) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // Build the UI using the ViewModel's current state
    return Scaffold(
      appBar: AppBar(
        title: const Text('Appointments'),
        actions: [
          // Session control buttons
          if (!_viewModel!.isSessionActive)
            IconButton(
              icon: const Icon(Icons.play_arrow),
              onPressed: () =>
                  _performViewModelOperation((vm) => vm.startSession()),
              tooltip: 'Start Session',
            )
          else if (!_viewModel!.isSessionPaused)
            IconButton(
              icon: const Icon(Icons.pause),
              onPressed: () =>
                  _performViewModelOperation((vm) => vm.pauseSession()),
              tooltip: 'Pause Session',
            )
          else
            IconButton(
              icon: const Icon(Icons.play_arrow),
              onPressed: () =>
                  _performViewModelOperation((vm) => vm.resumeSession()),
              tooltip: 'Resume Session',
            ),
          if (_viewModel!.isSessionActive)
            IconButton(
              icon: const Icon(Icons.stop),
              onPressed: () =>
                  _performViewModelOperation((vm) => vm.resetSession()),
              tooltip: 'End Session',
            ),
        ],
      ),
      body: Column(
        children: [
          // Date Selection
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Select Date:',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _viewModel!.availableDates.map((date) {
                      final isSelected = _viewModel!.selectedDate != null &&
                          _viewModel!.selectedDate!.year == date.year &&
                          _viewModel!.selectedDate!.month == date.month &&
                          _viewModel!.selectedDate!.day == date.day;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isSelected ? Colors.green : null,
                          ),
                          onPressed: () {
                            // Perform date selection safely
                            _performViewModelOperation(
                                (vm) async => vm.selectDate(date));
                          },
                          child: Text(DateFormat('MMM d').format(date)),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),

          // Session Timer
          if (_viewModel!.isSessionActive)
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.green.withOpacity(0.1),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.timer, color: Colors.green),
                  const SizedBox(width: 8),
                  Text(
                    'Session Duration: ${_viewModel!.getSessionDuration()}',
                    style: const TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

          // Appointments List
          Expanded(
            child: _viewModel!.isLoading
                ? const Center(child: CircularProgressIndicator())
                : _viewModel!.appointments.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.event_busy,
                              size: 64,
                              color: Colors.grey,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No appointments for ${DateFormat('MMM d').format(_viewModel!.selectedDate!)}',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    color: Colors.grey,
                                  ),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () => _performViewModelOperation(
                            (vm) => vm.refreshAppointments()),
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: _viewModel!.appointments.length,
                          itemBuilder: (context, index) {
                            final appointment = _viewModel!.appointments[index];
                            return AppointmentCard(
                              appointment: appointment,
                              isSessionActive: _viewModel!.isSessionActive,
                              onComplete: appointment['status'] == 'pending'
                                  ? () => _performViewModelOperation(
                                      (vm) => vm.markAppointmentComplete(
                                            appointment['appointmentId'],
                                          ))
                                  : null,
                              onPrint: () => _printAppointmentCard(appointment),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
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
}
