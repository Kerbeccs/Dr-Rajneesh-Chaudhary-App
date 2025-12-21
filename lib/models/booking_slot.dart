class BookingSlot {
  final String time;
  final int capacity;
  int booked;
  final int seatNumber;
  bool isDisabled;

  BookingSlot({
    required this.time,
    required this.capacity,
    this.booked = 0,
    required this.seatNumber,
    this.isDisabled = false,
  });

  bool canBook() {
    return booked < capacity && !isDisabled;
  }

  void book() {
    if (canBook()) {
      booked++;
    }
  }
}
