import 'package:intl/intl.dart';
import 'lib/viewmodels/booking_view_model.dart';

void main() async {
  // This is a simple test to verify that our BookingViewModel changes work correctly

  // Create a BookingViewModel
  final viewModel = BookingViewModel();

  // Get available dates
  final dates = viewModel.availableDates;
  print('Available dates:');
  for (final date in dates) {
    print(' - ${DateFormat('yyyy-MM-dd').format(date)}');
  }

  // Select the first date
  final date1 = dates[0];
  viewModel.selectDate(date1);
  print('\nSelected date 1: ${DateFormat('yyyy-MM-dd').format(date1)}');

  // Book a slot on the first date
  print('Slots for date 1 before booking:');
  for (final slot in viewModel.slots) {
    print(' - ${slot.time}: ${slot.capacity - slot.booked}/${slot.capacity}');
  }

  viewModel.setSelectedSlot(viewModel.slots[0]);
  await viewModel.bookSlot(viewModel.slots[0].seatNumber);

  print('\nSlots for date 1 after booking:');
  for (final slot in viewModel.slots) {
    print(' - ${slot.time}: ${slot.capacity - slot.booked}/${slot.capacity}');
  }

  // Select the second date
  final date2 = dates[1];
  viewModel.selectDate(date2);
  print('\nSelected date 2: ${DateFormat('yyyy-MM-dd').format(date2)}');

  // Check slots for the second date
  print('Slots for date 2:');
  for (final slot in viewModel.slots) {
    print(' - ${slot.time}: ${slot.capacity - slot.booked}/${slot.capacity}');
  }

  // Go back to the first date and verify the slot is still booked
  viewModel.selectDate(date1);
  print('\nBack to date 1: ${DateFormat('yyyy-MM-dd').format(date1)}');

  print('Slots for date 1 (should still show booked):');
  for (final slot in viewModel.slots) {
    print(' - ${slot.time}: ${slot.capacity - slot.booked}/${slot.capacity}');
  }
}
