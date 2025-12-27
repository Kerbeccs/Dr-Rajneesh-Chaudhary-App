import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../viewmodels/doctor_appointments_view_model.dart';
import '../widgets/appointment_card.dart';
import '../../services/parcha_print_service.dart';

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

          // Time Slot Selection (only show if date is selected)
          if (_viewModel!.selectedDate != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Select Time Slot:',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                _viewModel!.selectedTimeSlot == 'morning'
                                    ? Colors.blue
                                    : null,
                          ),
                          onPressed: () {
                            _performViewModelOperation(
                                (vm) async => vm.selectTimeSlot('morning'));
                          },
                          child: const Text('Morning\n9:30-2:30',
                              textAlign: TextAlign.center),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                _viewModel!.selectedTimeSlot == 'afternoon'
                                    ? Colors.blue
                                    : null,
                          ),
                          onPressed: () {
                            _performViewModelOperation(
                                (vm) async => vm.selectTimeSlot('afternoon'));
                          },
                          child: const Text('Afternoon\n3:00-5:00',
                              textAlign: TextAlign.center),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                _viewModel!.selectedTimeSlot == 'evening'
                                    ? Colors.blue
                                    : null,
                          ),
                          onPressed: () {
                            _performViewModelOperation(
                                (vm) async => vm.selectTimeSlot('evening'));
                          },
                          child: const Text('Evening\n5:30-8:00',
                              textAlign: TextAlign.center),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
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
            child: _viewModel!.selectedTimeSlot == null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.access_time,
                          size: 64,
                          color: Colors.grey,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Please select a time slot',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: Colors.grey,
                                  ),
                        ),
                      ],
                    ),
                  )
                : _viewModel!.isLoading
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
                                  'No appointments for ${DateFormat('MMM d').format(_viewModel!.selectedDate!)} - ${_viewModel!.selectedTimeSlot}',
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
                                final appointment =
                                    _viewModel!.appointments[index];
                            return AppointmentCard(
                              appointment: appointment,
                              isSessionActive: _viewModel!.isSessionActive,
                              onComplete: appointment['status'] == 'pending'
                                  ? () => _performViewModelOperation(
                                      (vm) => vm.markAppointmentComplete(
                                            appointment['appointmentId'],
                                          ))
                                  : null,
                                  onPrint: () =>
                                      _printAppointmentCard(appointment),
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
    await ParchaPrintService.printPatientCard(
      appointment: appt,
      onError: _showSnack,
    );
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
