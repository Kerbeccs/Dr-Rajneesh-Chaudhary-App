import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../viewmodels/ticket_view_model.dart';
import '../../models/doctor_scheduler.dart';
import 'dart:async';
import 'dart:math';

class AppointmentTicket extends StatefulWidget {
  const AppointmentTicket({super.key});

  @override
  State<AppointmentTicket> createState() => _AppointmentTicketState();
}

class _AppointmentTicketState extends State<AppointmentTicket> {
  bool _isLoading = true;
  String? _errorMessage;
  Map<String, dynamic>? _cachedStatus;
  DateTime? _lastFetchTime;
  static const _cacheDuration = Duration(seconds: 30);
  static const _maxRetries = 3;
  int _retryCount = 0;
  bool _isDisposed = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _startRefreshTimer();
    // Set loading to false after a short delay to ensure data is loaded
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted && !_isDisposed) {
        setState(() {
          _isLoading = false;
        });
      }
    });
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(_cacheDuration, (timer) {
      if (!_isDisposed && mounted) {
        setState(() {
          _lastFetchTime = null; // Force refresh
        });
      }
    });
  }

  Future<Map<String, dynamic>> _getPatientStatus(
      String patientId, DoctorScheduler scheduler) async {
    if (_isDisposed) {
      throw Exception('Widget is disposed');
    }

    try {
      // Check cache first
      if (_cachedStatus != null && _lastFetchTime != null) {
        if (DateTime.now().difference(_lastFetchTime!) < _cacheDuration) {
          return _cachedStatus!;
        }
      }

      // If cache is invalid or doesn't exist, fetch new data
      final status = scheduler.getPatientStatus(patientId);
      if (!_isDisposed) {
        setState(() {
          _cachedStatus = status;
          _lastFetchTime = DateTime.now();
          _retryCount = 0;
          _isLoading = false; // Set loading to false after getting status
        });
      }
      return status;
    } catch (e) {
      if (e is FirebaseException && e.code == 'too-many-attempts') {
        if (_retryCount < _maxRetries && !_isDisposed) {
          _retryCount++;
          await Future.delayed(Duration(seconds: pow(2, _retryCount).toInt()));
          return _getPatientStatus(patientId, scheduler);
        }

        if (_cachedStatus != null) {
          return _cachedStatus!;
        }
        throw Exception(
            'Unable to fetch status after $_maxRetries attempts. Please try again later.');
      }
      rethrow;
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isDisposed) {
      return const SizedBox.shrink();
    }

    final ticketViewModel = Provider.of<TicketViewModel>(context);
    final scheduler = DoctorScheduler();

    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Your Appointment Ticket',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          _buildInfoRow(
              'Patient Name', ticketViewModel.patientName, Colors.black87),
          _buildInfoRow(
              'Doctor Name', ticketViewModel.doctorName, Colors.black87),
          if (ticketViewModel.bookedSlots.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'No active appointments found.',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
              ),
            )
          else ...[
            const SizedBox(height: 20),
            const Text(
              'Current Appointment Status',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            ...ticketViewModel.bookedSlots.map((slot) {
              return FutureBuilder<Map<String, dynamic>>(
                future: _getPatientStatus(slot['appointmentId'], scheduler),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Text(
                              'Error: ${snapshot.error}',
                              style: const TextStyle(color: Colors.red),
                            ),
                            const SizedBox(height: 10),
                            ElevatedButton(
                              onPressed: _isDisposed
                                  ? null
                                  : () {
                                      setState(() {
                                        _isLoading = true;
                                        _errorMessage = null;
                                        _retryCount = 0;
                                      });
                                    },
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  final status = snapshot.data!;
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
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Ticket #${slot['slotNumber']}',
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Status: ${status['data']['currentStatus'] ?? 'Waiting'}',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Column(
                                    children: [
                                      Text(
                                        slot['time'],
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                      Text(
                                        slot['date'],
                                        style: const TextStyle(
                                          fontSize: 14,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const Divider(color: Colors.white30),
                            if (status['data']['queuePosition'] != null)
                              _buildInfoRow(
                                  'Your Position',
                                  '${status['data']['queuePosition']}',
                                  Colors.white),
                            if (status['data']['waitingTimeMinutes'] != null)
                              _buildInfoRow(
                                  'Estimated Wait',
                                  '${status['data']['waitingTimeMinutes']} minutes',
                                  Colors.white),
                            if (status['data']['estimatedCallTime'] != null)
                              _buildInfoRow(
                                  'Expected Call Time',
                                  status['data']['estimatedCallTime'],
                                  Colors.white),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            }),
          ],
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _isDisposed ? null : () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, Color textColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: textColor.withOpacity(0.8),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}
