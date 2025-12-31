import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'dart:ui' as ui;
import 'dart:io' if (dart.library.html) 'dart:html' as io;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';

/// Shared service for printing patient details on parcha
class ParchaPrintService {
  static Future<void> printPatientCard({
    required Map<String, dynamic> appointment,
    required Function(String) onError,
  }) async {
    try {
      final tokenId = appointment['patientToken'] as String?;
      if (tokenId == null || tokenId.isEmpty) {
        onError('Missing token id');
        return;
      }

      // 1) Load patient details by tokenId from 'patients'
      final patSnap = await FirebaseFirestore.instance
          .collection('patients')
          .where('tokenId', isEqualTo: tokenId)
          .limit(1)
          .get();
      if (patSnap.docs.isEmpty) {
        onError('Patient record not found');
        return;
      }
      final p = patSnap.docs.first.data();

      final name = (p['name'] ?? '').toString();
      final age = (p['age'] ?? '').toString();
      final weight = (p['weightKg'] ?? '').toString();
      final sex = (p['sex'] ?? '').toString();
      final phone = (p['mobileNumber'] ?? '').toString();
      final token = (p['tokenId'] ?? '').toString();
      final address = (p['address'] ?? '').toString();

      // Get dates for parcha printing
      String formattedAppointmentDate = ''; // Date for which booking is made
      String formattedBookingDate = ''; // lastVisited (shown as booking date)
      String formattedExpiryDate = ''; // lastVisited + 4 days
      DateTime? appointmentDate;
      DateTime? lastVisited;

      // Get appointment date from appointment database
      final dateField = appointment['date'];
      if (dateField != null && dateField.toString().isNotEmpty) {
        try {
          if (dateField.toString().contains('-')) {
            appointmentDate = DateTime.parse(dateField.toString());
          }
        } catch (e) {
          print('Error parsing date field: $e');
        }
      }

      // If 'date' didn't work, try 'appointmentDate' field
      if (appointmentDate == null) {
        final appointmentDateField = appointment['appointmentDate'];
        if (appointmentDateField != null &&
            appointmentDateField.toString().isNotEmpty) {
          try {
            if (appointmentDateField.toString().contains('-')) {
              appointmentDate = DateTime.parse(appointmentDateField.toString());
            }
          } catch (e) {
            print('Error parsing appointmentDate: $e');
          }
        }
      }

      // If still no date, try createdAt timestamp as fallback
      if (appointmentDate == null && appointment['createdAt'] != null) {
        try {
          final createdAt = appointment['createdAt'];
          if (createdAt is Timestamp) {
            appointmentDate = createdAt.toDate();
          } else if (createdAt is DateTime) {
            appointmentDate = createdAt;
          }
        } catch (e) {
          print('Error parsing createdAt: $e');
        }
      }

      // Format appointment date
      if (appointmentDate != null) {
        formattedAppointmentDate =
            DateFormat('dd/MM/yyyy').format(appointmentDate);
      } else {
        formattedAppointmentDate = 'N/A';
      }

      // Get lastVisited from patient record for booking date and expiry
      try {
        final lastVisitedField = p['lastVisited'];

        if (lastVisitedField != null) {
          if (lastVisitedField is Timestamp) {
            lastVisited = lastVisitedField.toDate();
          } else if (lastVisitedField is String) {
            lastVisited = DateTime.parse(lastVisitedField);
          } else if (lastVisitedField is DateTime) {
            lastVisited = lastVisitedField;
          }
        }

        if (lastVisited != null) {
          // Booking date shows lastVisited
          formattedBookingDate = DateFormat('dd/MM/yyyy').format(lastVisited);
          // Expiry date is lastVisited + 4 days (5 days total validity)
          final expiryDate = lastVisited.add(const Duration(days: 4));
          formattedExpiryDate = DateFormat('dd/MM/yyyy').format(expiryDate);
        } else {
          formattedBookingDate = 'N/A';
          formattedExpiryDate = 'N/A';
        }
      } catch (e) {
        print('Error parsing lastVisited: $e');
        formattedBookingDate = 'N/A';
        formattedExpiryDate = 'N/A';
      }

      // 2) Load base image from assets to get dimensions (for alignment)
      final byteData = await rootBundle.load('assets/logos/parcha.jpeg');
      final Uint8List bytes = byteData.buffer.asUint8List();
      final ui.Codec codec = await ui.instantiateImageCodec(bytes);
      final ui.FrameInfo frame = await codec.getNextFrame();
      final ui.Image baseImage = frame.image;

      // 3) Create white overlay canvas (same size as parcha for perfect alignment)
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final ui.Canvas canvas = ui.Canvas(recorder);
      final paint = ui.Paint();

      // Draw white background (same size as parcha.jpeg)
      paint.color = const ui.Color(0xFFFFFFFF); // White background
      canvas.drawRect(
        Rect.fromLTWH(
            0, 0, baseImage.width.toDouble(), baseImage.height.toDouble()),
        paint,
      );

      // Positioning constants
      const double topPadding = 10;
      const double rightMargin = 40;
      const double leftMargin = 40;
      const double gapY = 44;
      const double tokenColumnWidth = 400;
      const double phoneColumnWidth = 270;
      const double columnGap = 0;

      void textPainter(String text, double rightEdgeX, double y,
          {double fontSize = 28,
          ui.Color color = const ui.Color(0xFF000000),
          ui.TextAlign align = ui.TextAlign.right,
          double? maxWidth,
          double? leftX}) {
        final ui.ParagraphBuilder builder = ui.ParagraphBuilder(
          ui.ParagraphStyle(
            textAlign: align,
            fontSize: fontSize,
            maxLines: 1,
          ),
        )
          ..pushStyle(ui.TextStyle(color: color))
          ..addText(text);
        final width = maxWidth ?? (rightEdgeX - (leftX ?? leftMargin));
        final ui.Paragraph paragraph = builder.build()
          ..layout(ui.ParagraphConstraints(width: width));
        final drawX = leftX ?? (rightEdgeX - width);
        canvas.drawParagraph(paragraph, ui.Offset(drawX, y));
      }

      double startY = topPadding;
      startY += gapY * 5; // Moved down by one line

      // Token column at right edge, Phone on the left
      final double tokenColumnRightX = baseImage.width - rightMargin;
      final double phoneRightX =
          tokenColumnRightX - tokenColumnWidth - columnGap;

      // Token and Phone on the same line
      textPainter('Phone: $phone', phoneRightX, startY,
          align: ui.TextAlign.right, maxWidth: phoneColumnWidth);
      textPainter('Token: $token', tokenColumnRightX, startY,
          align: ui.TextAlign.right, maxWidth: tokenColumnWidth);
      startY += gapY * 1.5; // Increased gap between row 1 and row 2

      // Booking Date, Appointment Date, and Expiry Date in one row spanning full width
      final double fullWidth = baseImage.width - leftMargin - rightMargin;
      // Give more space to Appointment Date (40%), Booking and Expiry get 30% each
      final double bookingDateWidth = fullWidth * 0.35;
      final double appointmentDateWidth = fullWidth * 0.38;
      final double expiryDateWidth = fullWidth * 0.30;
      const double dateStartX = leftMargin;
      // Shift appointment and expiry dates to the right to make room for booking date
      const double rightShift = 20.0;

      textPainter('Booking Date: $formattedBookingDate',
          dateStartX + bookingDateWidth, startY,
          align: ui.TextAlign.left,
          maxWidth: bookingDateWidth,
          leftX: dateStartX);
      textPainter(
          'Appointment Date: $formattedAppointmentDate',
          dateStartX + bookingDateWidth + appointmentDateWidth + rightShift,
          startY,
          align: ui.TextAlign.left,
          maxWidth: appointmentDateWidth,
          leftX: dateStartX + bookingDateWidth + rightShift);
      textPainter(
          'Expiry Date: $formattedExpiryDate',
          dateStartX +
              bookingDateWidth +
              appointmentDateWidth +
              expiryDateWidth +
              rightShift,
          startY,
          align: ui.TextAlign.left,
          maxWidth: expiryDateWidth,
          leftX: dateStartX +
              bookingDateWidth +
              appointmentDateWidth +
              rightShift);
      startY += gapY;
      textPainter('Name: $name', tokenColumnRightX, startY,
          align: ui.TextAlign.right, maxWidth: tokenColumnWidth);
      startY += gapY;
      textPainter('Age: $age', tokenColumnRightX, startY,
          align: ui.TextAlign.right, maxWidth: tokenColumnWidth);
      startY += gapY;
      textPainter('Sex: $sex', tokenColumnRightX, startY,
          align: ui.TextAlign.right, maxWidth: tokenColumnWidth);
      startY += gapY;
      textPainter('Weight: $weight', tokenColumnRightX, startY,
          align: ui.TextAlign.right, maxWidth: tokenColumnWidth);
      startY += gapY;
      // Address label on one line
      textPainter('Address:', tokenColumnRightX, startY,
          align: ui.TextAlign.right, maxWidth: tokenColumnWidth);
      startY += gapY;
      // Address text on next line (max 50 characters)
      textPainter(address, tokenColumnRightX, startY,
          align: ui.TextAlign.right, maxWidth: tokenColumnWidth);

      final ui.Picture picture = recorder.endRecording();
      final ui.Image finalImage = await picture.toImage(
        baseImage.width,
        baseImage.height,
      );
      final ByteData? pngBytes =
          await finalImage.toByteData(format: ui.ImageByteFormat.png);
      if (pngBytes == null) {
        onError('Failed to compose image');
        return;
      }

      final Uint8List imageBytes = pngBytes.buffer.asUint8List();

      // 4) Share - use different approach for web vs mobile
      if (kIsWeb) {
        // For web: Use XFile.fromData() which works without file system
        final xFile = XFile.fromData(
          imageBytes,
          mimeType: 'image/png',
          name: 'parcha_$token.png',
        );
        await Share.shareXFiles([xFile], text: 'Patient Details');
      } else {
        // For mobile: Save to temporary file
        final dir = await getTemporaryDirectory();
        final file = io.File('${dir.path}/parcha_$token.png');
        await file.writeAsBytes(imageBytes, flush: true);
        await Share.shareXFiles([XFile(file.path)], text: 'Patient Details');
      }
    } catch (e) {
      onError('Print failed: $e');
    }
  }
}
