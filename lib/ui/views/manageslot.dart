import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../viewmodels/booking_view_model.dart';
import 'package:intl/intl.dart';

class ManageSlotsScreen extends StatefulWidget {
  const ManageSlotsScreen({super.key});

  @override
  State<ManageSlotsScreen> createState() => _ManageSlotsScreenState();
}

class _ManageSlotsScreenState extends State<ManageSlotsScreen> {
  @override
  void initState() {
    super.initState();
    // Load disabled slots when screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final bookingViewModel = Provider.of<BookingViewModel>(context, listen: false);
      if (bookingViewModel.selectedDate != null) {
        _loadDisabledSlots(bookingViewModel, bookingViewModel.selectedDate!);
      } else {
        // Select today by default and load
        final today = DateTime.now();
        bookingViewModel.selectDate(today);
        _loadDisabledSlots(bookingViewModel, today);
      }
    });
  }

  Future<void> _loadDisabledSlots(BookingViewModel viewModel, DateTime date) async {
    final dateKey = DateFormat('yyyy-MM-dd').format(date);
    // Trigger reload from Firestore
    await viewModel.loadDisabledTimeSlotsForDate(dateKey);
  }

  @override
  Widget build(BuildContext context) {
    final bookingViewModel = Provider.of<BookingViewModel>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Slots'),
      ),
      body: Column(
        children: [
          // Date selector
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: bookingViewModel.availableDates.map((date) {
                  final isSelected =
                      bookingViewModel.selectedDate?.day == date.day;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isSelected ? Colors.green : null,
                      ),
                      onPressed: () {
                        bookingViewModel.selectDate(date);
                        _loadDisabledSlots(bookingViewModel, date);
                      },
                      child: Text(
                        '${date.day}/${date.month}',
                        style: TextStyle(
                          color: isSelected ? Colors.white : null,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          // Time slots list
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                _buildTimeSlotCard(
                  context,
                  bookingViewModel,
                  'Morning',
                  '9:30 AM - 2:30 PM',
                  'morning',
                  70,
                ),
                const SizedBox(height: 16),
                _buildTimeSlotCard(
                  context,
                  bookingViewModel,
                  'Afternoon',
                  '3:00 PM - 5:00 PM',
                  'afternoon',
                  30,
                ),
                const SizedBox(height: 16),
                _buildTimeSlotCard(
                  context,
                  bookingViewModel,
                  'Evening',
                  '5:30 PM - 8:00 PM',
                  'evening',
                  50,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeSlotCard(
    BuildContext context,
    BookingViewModel viewModel,
    String title,
    String timeRange,
    String timeSlot,
    int totalSeats,
  ) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
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
                      title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      timeRange,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
                Switch(
                  value: !viewModel.isTimeSlotDisabled(timeSlot),
                  onChanged: (bool value) async {
                    try {
                      await viewModel.toggleTimeSlotAvailability(
                        timeSlot,
                        viewModel.selectedDate!,
                      );
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Failed to update slot: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Total Seats: $totalSeats',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
