import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Patient Dashboard"),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              // Add logout functionality later
              Navigator.pushReplacementNamed(context, '/login');
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: GridView.count(
          crossAxisCount: 2,
          mainAxisSpacing: 20,
          crossAxisSpacing: 20,
          children: [
            _buildMenuCard(
              context,
              'Upload Report',
              Icons.upload_file,
              Colors.blue,
              () {
                // Add upload report functionality
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Upload Report - Coming Soon')),
                );
              },
            ),
            _buildMenuCard(
              context,
              'Book Appointment',
              Icons.calendar_today,
              Colors.green,
              () {
                // Add book appointment functionality
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Book Appointment - Coming Soon')),
                );
              },
            ),
            _buildMenuCard(
              context,
              'Feedback',
              Icons.feedback,
              Colors.orange,
              () {
                // Add feedback functionality
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Feedback - Coming Soon')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuCard(BuildContext context, String title, IconData icon,
      Color color, VoidCallback onTap) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withOpacity(0.7),
                color,
              ],
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 50,
                color: Colors.white,
              ),
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

class BookingSlot {
  final String time;
  final int capacity;
  int booked;

  BookingSlot(this.time, this.capacity) : booked = 0;

  bool canBook() => booked < capacity;

  void book() {
    if (canBook()) {
      booked++;
    } else {
      throw Exception('Slot is full');
    }
  }
}

class BookingManager {
  final DateTime bookingDate;
  final List<BookingSlot> slots;

  BookingManager()
      : bookingDate = DateTime.now().add(const Duration(days: 4)),
        slots = [
          BookingSlot('9-10am', 6),
          BookingSlot('2:30-3:30pm', 10),
          BookingSlot('8-9pm', 10),
        ];

  bool isBookingDateValid(DateTime date) {
    return date.year == bookingDate.year &&
        date.month == bookingDate.month &&
        date.day == bookingDate.day;
  }

  void bookSlot(String time) {
    final slot = slots.firstWhere((slot) => slot.time == time, orElse: () => throw Exception('Invalid slot time'));
    if (slot.canBook()) {
      slot.book();
      print('Booking successful for $time');
    } else {
      print('Slot $time is full');
    }
  }
}

// Usage example
void main() {
  final bookingManager = BookingManager();

  // Check if the booking date is valid
  if (bookingManager.isBookingDateValid(DateTime.now().add(const Duration(days: 4)))) {
    try {
      bookingManager.bookSlot('9-10am');
      bookingManager.bookSlot('2:30-3:30pm');
      // Attempt to book more slots as needed
    } catch (e) {
      print(e);
    }
  } else {
    print('Bookings can only be made for 4 days from now');
  }
}
