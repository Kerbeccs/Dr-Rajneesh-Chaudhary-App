import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/material.dart';

class WhatsAppService {
  static const String doctorNumber = '9415148932';

  /// Sends a WhatsApp message to the doctor about a new booking
  static Future<void> sendBookingNotification({
    required String patientName,
    required String patientToken,
    required int seatNumber,
    required String appointmentDate,
    required String appointmentTime,
  }) async {
    try {
      final message = _buildBookingMessage(
        patientName: patientName,
        patientToken: patientToken,
        seatNumber: seatNumber,
        appointmentDate: appointmentDate,
        appointmentTime: appointmentTime,
      );

      await _sendWhatsAppMessage(message);
    } catch (e) {
      debugPrint('Error sending WhatsApp notification: $e');
    }
  }

  /// Builds the booking notification message
  static String _buildBookingMessage({
    required String patientName,
    required String patientToken,
    required int seatNumber,
    required String appointmentDate,
    required String appointmentTime,
  }) {
    return '''🏥 *New Appointment Booking*

👤 *Patient:* $patientName
🎫 *Token:* $patientToken
🪑 *Seat No:* $seatNumber
📅 *Date:* $appointmentDate
⏰ *Time:* $appointmentTime

✅ Booking confirmed successfully!''';
  }

  /// Sends WhatsApp message using URL launcher
  static Future<void> _sendWhatsAppMessage(String message) async {
    final encodedMessage = Uri.encodeComponent(message);
    final whatsappUrl = 'https://wa.me/$doctorNumber?text=$encodedMessage';

    final uri = Uri.parse(whatsappUrl);

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      debugPrint('Could not launch WhatsApp');
    }
  }

  /// Alternative method using whatsapp:// URL scheme (for mobile apps)
  static Future<void> sendWhatsAppMessageMobile(String message) async {
    final encodedMessage = Uri.encodeComponent(message);
    final whatsappUrl =
        'whatsapp://send?phone=$doctorNumber&text=$encodedMessage';

    final uri = Uri.parse(whatsappUrl);

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      // Fallback to web version
      final webUrl = 'https://wa.me/$doctorNumber?text=$encodedMessage';
      final webUri = Uri.parse(webUrl);
      if (await canLaunchUrl(webUri)) {
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
      }
    }
  }
}
