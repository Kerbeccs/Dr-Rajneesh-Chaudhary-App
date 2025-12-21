import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../viewmodels/ticket_view_model.dart';
import 'dart:async';
import 'package:intl/intl.dart';

class TicketDetailsScreen extends StatefulWidget {
  const TicketDetailsScreen({super.key});

  @override
  State<TicketDetailsScreen> createState() => _TicketDetailsScreenState();
}

class _TicketDetailsScreenState extends State<TicketDetailsScreen> {
  bool _isDisposed = false;
  Timer? _refreshTimer;
  final Map<String, bool> _loadingStates =
      {}; // Track loading state per appointment
  final ScrollController _scrollController =
      ScrollController(); // Preserve scroll position
  final Map<String, Future<Map<String, dynamic>>> _statusFutures =
      {}; // Cache futures to prevent flickering

  @override
  void initState() {
    super.initState();
    _startRefreshTimer();
    // Load initial data
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_isDisposed) {
        final ticketViewModel =
            Provider.of<TicketViewModel>(context, listen: false);
        ticketViewModel.loadBookedSlots();
      }
    });
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (!_isDisposed && mounted) {
        final ticketViewModel =
            Provider.of<TicketViewModel>(context, listen: false);
        // Refresh data periodically and clear cached futures
        ticketViewModel.clearCache();
        // Clear cached futures to allow refresh
        setState(() {
          _statusFutures.clear();
        });
      }
    });
  }

  @override
  void dispose() {
    _isDisposed = true;
    _refreshTimer?.cancel();
    _scrollController.dispose(); // Dispose scroll controller
    super.dispose();
  }

  Future<void> _refreshStatus(
      String appointmentId, TicketViewModel viewModel) async {
    if (_isDisposed) return;

    setState(() {
      _loadingStates[appointmentId] = true;
      // Clear cached future to force refresh
      _statusFutures.remove(appointmentId);
    });

    try {
      // Create new future and cache it
      _statusFutures[appointmentId] = viewModel.getPatientStatus(appointmentId);
      await _statusFutures[appointmentId];
    } catch (e) {
      if (mounted && !_isDisposed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error refreshing status: ${e.toString()}'),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () => _refreshStatus(appointmentId, viewModel),
            ),
          ),
        );
      }
    } finally {
      if (mounted && !_isDisposed) {
        setState(() {
          _loadingStates[appointmentId] = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isDisposed) {
      return const SizedBox.shrink();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Appointment Details'),
        centerTitle: true,
        actions: [
          Consumer<TicketViewModel>(
            builder: (context, viewModel, child) {
              return IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh',
                onPressed: viewModel.isLoading
                    ? null
                    : () => viewModel.loadBookedSlots(),
              );
            },
          ),
        ],
      ),
      body: Consumer<TicketViewModel>(
        builder: (context, ticketViewModel, child) {
          return SingleChildScrollView(
            controller:
                _scrollController, // Use scroll controller to preserve position
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Patient and Doctor Info Card
                  _buildPatientInfoCard(ticketViewModel),
                  const SizedBox(height: 8),
                  _buildDoctorStatusIndicator(ticketViewModel),
                  const SizedBox(height: 20),

                  // Scheduler Integration Status (if available)
                  if (ticketViewModel.isSchedulerIntegrated)
                    _buildSchedulerStatusCard(),

                  // Error Message Display
                  if (ticketViewModel.hasError)
                    _buildErrorCard(ticketViewModel),

                  // Loading Indicator
                  if (ticketViewModel.isLoading)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20.0),
                        child: CircularProgressIndicator(),
                      ),
                    ),

                  // Appointment Status
                  if (ticketViewModel.validSlots.isEmpty &&
                      !ticketViewModel.isLoading)
                    _buildNoAppointmentsCard()
                  else
                    ...ticketViewModel.validSlots.map((slot) {
                      final appointmentId = slot['appointmentId'] as String;
                      return _buildAppointmentCard(
                          slot, ticketViewModel, appointmentId);
                    }),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPatientInfoCard(TicketViewModel viewModel) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.person_outline, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  'Patient Information',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const Divider(),
            _buildInfoRow(
              'Patient Name',
              viewModel.patientName,
              const Color.fromARGB(255, 25, 139, 165),
            ),
            _buildInfoRow(
              'Doctor Name',
              viewModel.doctorName,
              const Color.fromARGB(255, 25, 139, 165),
            ),
            if (viewModel.validSlots.isNotEmpty)
              _buildInfoRow(
                'Current Wait Time',
                viewModel.waitingTime,
                Colors.orange,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSchedulerStatusCard() {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'Real-time scheduling active',
              style: TextStyle(
                color: Colors.green,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard(TicketViewModel viewModel) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16),
      color: Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                viewModel.errorMessage ?? 'An error occurred',
                style: const TextStyle(color: Colors.red),
              ),
            ),
            TextButton(
              onPressed: () {
                viewModel.clearCache();
                viewModel.loadBookedSlots();
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoAppointmentsCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Icon(
              Icons.calendar_today_outlined,
              size: 48,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            const Text(
              'No pending appointments found',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'No appointments scheduled for today or tomorrow.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppointmentCard(Map<String, dynamic> slot,
      TicketViewModel viewModel, String appointmentId) {
    final isLoading = _loadingStates[appointmentId] ?? false;

    // Cache the future to prevent recreating it on every rebuild (fixes flickering)
    if (!_statusFutures.containsKey(appointmentId)) {
      _statusFutures[appointmentId] = viewModel.getPatientStatus(appointmentId);
    }

    return FutureBuilder<Map<String, dynamic>>(
      key: ValueKey(appointmentId), // Add key to preserve widget identity
      future: _statusFutures[appointmentId],
      builder: (context, snapshot) {
        // Handle different states
        if (snapshot.connectionState == ConnectionState.waiting || isLoading) {
          return _buildLoadingCard(slot);
        }

        if (snapshot.hasError) {
          return _buildErrorAppointmentCard(slot, snapshot.error.toString(),
              () {
            viewModel.retryStatusFetch(appointmentId);
            _refreshStatus(appointmentId, viewModel);
          });
        }

        final status = snapshot.data!;
        final statusData = status['data'] as Map<String, dynamic>?;
        final isFromScheduler = statusData?['isFromScheduler'] == true;

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 8),
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.blue.withOpacity(0.7),
                  Colors.blue,
                ],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header with ticket number and refresh button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'Ticket #${slot['slotNumber']}',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                if (isFromScheduler) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.green,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Text(
                                      'LIVE',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Status: ${statusData?['consultationStatus'] ?? statusData?['currentStatus'] ?? slot['status'] ?? 'Pending'}',
                              style: const TextStyle(
                                fontSize: 16,
                                color: Colors.white,
                              ),
                            ),
                            if (_isInConsultationStatus(statusData))
                              Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Row(
                                  children: [
                                    const Icon(Icons.play_arrow,
                                        color: Colors.yellow, size: 20),
                                    const SizedBox(width: 6),
                                    const Text(
                                      'Doctor is attending you now!',
                                      style: TextStyle(
                                        color: Colors.yellow,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    _buildConsultationTimer(
                                        statusData?['consultationStartTime']),
                                  ],
                                ),
                              ),
                            if (statusData?['consultationStartTime'] != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4.0),
                                child: Text(
                                  'Started at: ${_formatDateTime(statusData?['consultationStartTime'])}',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  slot['time'] ?? 'N/A',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                Text(
                                  _formatDate(slot['date']),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          IconButton(
                            onPressed: isLoading
                                ? null
                                : () =>
                                    _refreshStatus(appointmentId, viewModel),
                            icon: Icon(
                              Icons.refresh,
                              color: Colors.white.withOpacity(0.8),
                              size: 20,
                            ),
                            tooltip: 'Refresh Status',
                          ),
                        ],
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white30),

                  // Status information
                  if (statusData?['queuePosition'] != null)
                    _buildInfoRow(
                      'Patients Ahead',
                      '${(statusData!['queuePosition'] as int) - 1 < 0 ? 0 : (statusData['queuePosition'] as int) - 1}',
                      Colors.white,
                    ),

                  // Enhanced waiting time from scheduler or fallback
                  _buildInfoRow(
                    'Estimated Wait',
                    isFromScheduler &&
                            statusData?['accurateWaitingTime'] != null
                        ? statusData!['accurateWaitingTime']
                        : viewModel.getEnhancedWaitingTime(appointmentId),
                    Colors.white,
                  ),

                  if (statusData?['estimatedCallTime'] != null)
                    _buildInfoRow(
                      'Expected Call Time',
                      statusData!['estimatedCallTime'],
                      Colors.white,
                    ),

                  // Last updated timestamp
                  if (statusData?['lastUpdatedFromScheduler'] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Last updated: ${_formatTimestamp(statusData!['lastUpdatedFromScheduler'])}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.7),
                        ),
                      ),
                    ),

                  // Data source indicator
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      isFromScheduler ? 'Real-time data' : 'Estimated data',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withOpacity(0.6),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Patients seen today: ${viewModel.completedConsultationsToday} on ${viewModel.todayDate}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLoadingCard(Map<String, dynamic> slot) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.grey.withOpacity(0.3),
              Colors.grey.withOpacity(0.5),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Ticket #${slot['slotNumber']}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Loading status...',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorAppointmentCard(
      Map<String, dynamic> slot, String error, VoidCallback onRetry) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          color: Colors.red.shade100,
          border: Border.all(color: Colors.red.shade300),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Ticket #${slot['slotNumber']}',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.red.shade700,
                    ),
                  ),
                  Icon(
                    Icons.error_outline,
                    color: Colors.red.shade700,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Error loading status',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.red.shade700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                error,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.red.shade600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Retry'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade600,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, Color textColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: textColor.withOpacity(0.8),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String? dateString) {
    if (dateString == null) return 'N/A';

    try {
      final date = DateFormat('yyyy-MM-dd').parse(dateString);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final appointmentDate = DateTime(date.year, date.month, date.day);

      if (appointmentDate == today) {
        return 'Today';
      } else if (appointmentDate == today.add(const Duration(days: 1))) {
        return 'Tomorrow';
      } else {
        return DateFormat('MMM dd').format(date);
      }
    } catch (e) {
      return dateString;
    }
  }

  String _formatTimestamp(String timestamp) {
    try {
      final dateTime = DateTime.parse(timestamp);
      final now = DateTime.now();
      final difference = now.difference(dateTime);

      if (difference.inSeconds < 60) {
        return 'Just now';
      } else if (difference.inMinutes < 60) {
        return '${difference.inMinutes}m ago';
      } else {
        return DateFormat('HH:mm').format(dateTime);
      }
    } catch (e) {
      return 'Unknown';
    }
  }

  Widget _buildConsultationTimer(dynamic startTime) {
    if (startTime == null) return const SizedBox();
    DateTime? start;
    if (startTime is String) {
      start = DateTime.tryParse(startTime);
    } else if (startTime is DateTime) {
      start = startTime;
    }
    if (start == null) return const SizedBox();
    return _LiveTimerWidget(startTime: start);
  }

  String _formatDateTime(dynamic dateTime) {
    if (dateTime == null) return '';
    DateTime? dt;
    if (dateTime is String) {
      dt = DateTime.tryParse(dateTime);
    } else if (dateTime is DateTime) {
      dt = dateTime;
    }
    if (dt == null) return '';
    return DateFormat('yyyy-MM-dd HH:mm').format(dt);
  }

  // --- NEW: Helper to check in-consultation status robustly ---
  bool _isInConsultationStatus(Map<String, dynamic>? statusData) {
    if (statusData == null) return false;
    final statusFields = [
      statusData['consultationStatus'],
      statusData['currentStatus'],
      statusData['status'],
    ];
    for (final field in statusFields) {
      if (field == null) continue;
      final value = field
          .toString()
          .toLowerCase()
          .replaceAll('_', '')
          .replaceAll(' ', '');
      if (value == 'inconsultation' || value == 'inprogress') {
        return true;
      }
    }
    return false;
  }

  Widget _buildDoctorStatusIndicator(TicketViewModel viewModel) {
    Color statusColor;
    IconData statusIcon;
    String message = viewModel.doctorStatus;

    if (!viewModel.isDoctorSeeing && message.contains('not present')) {
      statusColor = Colors.grey;
      statusIcon = Icons.person_off;
    } else if (message.contains('break')) {
      statusColor = Colors.orange;
      statusIcon = Icons.coffee;
    } else if (viewModel.isDoctorSeeing) {
      statusColor = Colors.green;
      statusIcon = Icons.medical_services;
    } else {
      statusColor = Colors.grey;
      statusIcon = Icons.hourglass_empty;
    }

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            Icon(statusIcon, color: statusColor),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (viewModel.isDoctorSeeing &&
                      viewModel.sessionStartTime != null)
                    Text(
                      'Started at: ${DateFormat('hh:mm a').format(viewModel.sessionStartTime!)}',
                      style: TextStyle(
                        color: statusColor.withOpacity(0.7),
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveTimerWidget extends StatefulWidget {
  final DateTime startTime;
  const _LiveTimerWidget({required this.startTime});
  @override
  State<_LiveTimerWidget> createState() => _LiveTimerWidgetState();
}

class _LiveTimerWidgetState extends State<_LiveTimerWidget> {
  late Timer _timer;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _elapsed = DateTime.now().difference(widget.startTime);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        _elapsed = DateTime.now().difference(widget.startTime);
      });
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = _elapsed.inHours;
    final minutes = _elapsed.inMinutes % 60;
    final seconds = _elapsed.inSeconds % 60;
    return Text(
      'Time: ${twoDigits(hours)}:${twoDigits(minutes)}:${twoDigits(seconds)}',
      style: const TextStyle(
        color: Colors.yellow,
        fontWeight: FontWeight.bold,
        fontSize: 13,
      ),
    );
  }
}
