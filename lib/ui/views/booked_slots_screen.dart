import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../viewmodels/ticket_view_model.dart';

class BookedSlotsScreen extends StatefulWidget {
  const BookedSlotsScreen({super.key});

  @override
  State<BookedSlotsScreen> createState() => _BookedSlotsScreenState();
}

class _BookedSlotsScreenState extends State<BookedSlotsScreen> {
  @override
  void initState() {
    super.initState();
    // Refresh booked slots when screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<TicketViewModel>(context, listen: false).loadBookedSlots();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TicketViewModel>(
      builder: (context, viewModel, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('My Booked Slots'),
            elevation: 2,
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () => viewModel.loadBookedSlots(),
                tooltip: 'Refresh',
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: () async {
              await viewModel.loadBookedSlots();
            },
            child: viewModel.isLoading
                ? const Center(child: CircularProgressIndicator())
                : viewModel.bookedSlots.isEmpty
                    ? _buildEmptyState()
                    : _buildSlotsList(viewModel),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.event_busy,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No Appointments Booked',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Book your first appointment to see it here',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.grey[500],
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.add),
            label: const Text('Book Appointment'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlotsList(TicketViewModel viewModel) {
    // Group slots by status
    final upcomingSlots = viewModel.bookedSlots
        .where((slot) => _getSlotStatus(slot) == SlotStatus.upcoming)
        .toList();
    final completedSlots = viewModel.bookedSlots
        .where((slot) => _getSlotStatus(slot) == SlotStatus.completed)
        .toList();
    final cancelledSlots = viewModel.bookedSlots
        .where((slot) => _getSlotStatus(slot) == SlotStatus.cancelled)
        .toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (upcomingSlots.isNotEmpty) ...[
          _buildSectionHeader('Upcoming Appointments', upcomingSlots.length, Colors.green),
          ...upcomingSlots.map((slot) => _buildSlotCard(slot, SlotStatus.upcoming)),
          const SizedBox(height: 16),
        ],
        if (completedSlots.isNotEmpty) ...[
          _buildSectionHeader('Completed Appointments', completedSlots.length, Colors.blue),
          ...completedSlots.map((slot) => _buildSlotCard(slot, SlotStatus.completed)),
          const SizedBox(height: 16),
        ],
        if (cancelledSlots.isNotEmpty) ...[
          _buildSectionHeader('Cancelled Appointments', cancelledSlots.length, Colors.red),
          ...cancelledSlots.map((slot) => _buildSlotCard(slot, SlotStatus.cancelled)),
        ],
      ],
    );
  }

  Widget _buildSectionHeader(String title, int count, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 24,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              count.toString(),
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlotCard(Map<String, dynamic> slot, SlotStatus status) {
    final statusColor = _getStatusColor(status);
    final statusText = _getStatusText(status);
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: statusColor.withOpacity(0.2),
          width: 1,
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
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Seat ${slot['slotNumber'] ?? slot['seatNumber'] ?? 'N/A'}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: statusColor.withOpacity(0.3)),
                      ),
                      child: Text(
                        statusText,
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  slot['time'] ?? slot['appointmentTime'] ?? 'Time not set',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildInfoRow(
              context,
              'Date',
              _formatDate(slot['date'] ?? slot['appointmentDate']),
              Icons.calendar_today,
              statusColor,
            ),
            const SizedBox(height: 8),
            if (slot['estimatedTime'] != null) ...[
              _buildInfoRow(
                context,
                'Estimated Time',
                slot['estimatedTime'],
                Icons.access_time,
                statusColor,
              ),
              const SizedBox(height: 8),
            ],
            _buildInfoRow(
              context,
              'Status',
              slot['status'] ?? statusText,
              _getStatusIcon(status),
              statusColor,
            ),
            if (status == SlotStatus.upcoming) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: OutlinedButton.icon(
                      onPressed: () => _showCancelDialog(slot),
                      icon: const Icon(Icons.cancel_outlined, size: 16),
                      label: const Text('Cancel'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: ElevatedButton.icon(
                      onPressed: () => _showAppointmentDetails(slot),
                      icon: const Icon(Icons.info_outline, size: 16),
                      label: const Text('View Details'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(
    BuildContext context,
    String label,
    String value,
    IconData icon,
    Color accentColor,
  ) {
    return Row(
      children: [
        Icon(
          icon,
          size: 18,
          color: accentColor.withOpacity(0.7),
        ),
        const SizedBox(width: 10),
        Text(
          '$label:',
          style: TextStyle(
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
            fontSize: 14,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return 'Date not set';
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('MMM dd, yyyy').format(date);
    } catch (e) {
      return dateStr; // Return original if parsing fails
    }
  }

  SlotStatus _getSlotStatus(Map<String, dynamic> slot) {
    final status = slot['status']?.toString().toLowerCase();
    final dateStr = slot['date'] ?? slot['appointmentDate'];
    
    if (status == 'cancelled') return SlotStatus.cancelled;
    if (status == 'completed') return SlotStatus.completed;
    
    // Check if appointment date has passed
    if (dateStr != null) {
      try {
        final appointmentDate = DateTime.parse(dateStr);
        final now = DateTime.now();
        if (appointmentDate.isBefore(DateTime(now.year, now.month, now.day))) {
          return SlotStatus.completed;
        }
      } catch (e) {
        // If date parsing fails, assume upcoming
      }
    }
    
    return SlotStatus.upcoming;
  }

  Color _getStatusColor(SlotStatus status) {
    switch (status) {
      case SlotStatus.upcoming:
        return Colors.green;
      case SlotStatus.completed:
        return Colors.blue;
      case SlotStatus.cancelled:
        return Colors.red;
    }
  }

  String _getStatusText(SlotStatus status) {
    switch (status) {
      case SlotStatus.upcoming:
        return 'UPCOMING';
      case SlotStatus.completed:
        return 'COMPLETED';
      case SlotStatus.cancelled:
        return 'CANCELLED';
    }
  }

  IconData _getStatusIcon(SlotStatus status) {
    switch (status) {
      case SlotStatus.upcoming:
        return Icons.schedule;
      case SlotStatus.completed:
        return Icons.check_circle_outline;
      case SlotStatus.cancelled:
        return Icons.cancel_outlined;
    }
  }

  void _showCancelDialog(Map<String, dynamic> slot) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Appointment'),
        content: Text(
          'Are you sure you want to cancel your appointment for Seat ${slot['slotNumber'] ?? slot['seatNumber']}?'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _cancelAppointment(slot);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );
  }

  void _cancelAppointment(Map<String, dynamic> slot) async {
    try {
      final ticketViewModel = Provider.of<TicketViewModel>(context, listen: false);
      await ticketViewModel.cancelAppointment(slot['appointmentId'] ?? slot['id']);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Appointment cancelled successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to cancel appointment: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showAppointmentDetails(Map<String, dynamic> slot) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Appointment Details - Seat ${slot['slotNumber'] ?? slot['seatNumber']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow('Date', _formatDate(slot['date'] ?? slot['appointmentDate'])),
            _buildDetailRow('Time', slot['time'] ?? slot['appointmentTime'] ?? 'Not set'),
            _buildDetailRow('Status', slot['status'] ?? 'Pending'),
            if (slot['appointmentId'] != null)
              _buildDetailRow('Booking ID', slot['appointmentId']),
            if (slot['estimatedTime'] != null)
              _buildDetailRow('Estimated Time', slot['estimatedTime']),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }
}

enum SlotStatus {
  upcoming,
  completed,
  cancelled,
}