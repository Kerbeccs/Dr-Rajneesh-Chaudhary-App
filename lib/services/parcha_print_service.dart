import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'dart:ui' as ui;
import 'dart:io';
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

      // Get booking date from appointment database
      String formattedDate = '';
      String formattedExpiryDate = '';
      DateTime? bookingDate;

      // Try getting date from 'date' field first
      final dateField = appointment['date'];
      if (dateField != null && dateField.toString().isNotEmpty) {
        try {
          if (dateField.toString().contains('-')) {
            bookingDate = DateTime.parse(dateField.toString());
          }
        } catch (e) {
          print('Error parsing date field: $e');
        }
      }

      // If 'date' didn't work, try 'appointmentDate' field
      if (bookingDate == null) {
        final appointmentDate = appointment['appointmentDate'];
        if (appointmentDate != null && appointmentDate.toString().isNotEmpty) {
          try {
            if (appointmentDate.toString().contains('-')) {
              bookingDate = DateTime.parse(appointmentDate.toString());
            }
          } catch (e) {
            print('Error parsing appointmentDate: $e');
          }
        }
      }

      // If still no date, try createdAt timestamp as fallback
      if (bookingDate == null && appointment['createdAt'] != null) {
        try {
          final createdAt = appointment['createdAt'];
          if (createdAt is Timestamp) {
            bookingDate = createdAt.toDate();
          } else if (createdAt is DateTime) {
            bookingDate = createdAt;
          }
        } catch (e) {
          print('Error parsing createdAt: $e');
        }
      }

      // Format the dates if we got a valid booking date
      if (bookingDate != null) {
        formattedDate = DateFormat('dd/MM/yyyy').format(bookingDate);
        
        // Calculate expiry date (+4 days)
        // DateTime.add() automatically handles month boundaries
        final expiryDate = bookingDate.add(const Duration(days: 4));
        formattedExpiryDate = DateFormat('dd/MM/yyyy').format(expiryDate);
      } else {
        formattedDate = 'N/A';
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
        Rect.fromLTWH(0, 0, baseImage.width.toDouble(), baseImage.height.toDouble()),
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
          double? maxWidth}) {
        final ui.ParagraphBuilder builder = ui.ParagraphBuilder(
          ui.ParagraphStyle(
            textAlign: align,
            fontSize: fontSize,
            maxLines: 1,
          ),
        )
          ..pushStyle(ui.TextStyle(color: color))
          ..addText(text);
        final width = maxWidth ?? (rightEdgeX - leftMargin);
        final ui.Paragraph paragraph = builder.build()
          ..layout(ui.ParagraphConstraints(width: width));
        final drawX = rightEdgeX - width;
        canvas.drawParagraph(paragraph, ui.Offset(drawX, y));
      }

      double startY = topPadding;
      startY += gapY * 5;

      // Token column at right edge, Phone on the left
      final double tokenColumnRightX = baseImage.width - rightMargin;
      final double phoneRightX = tokenColumnRightX - tokenColumnWidth - columnGap;

      // Token and Phone on the same line
      textPainter('Phone: $phone', phoneRightX, startY,
          align: ui.TextAlign.right, maxWidth: phoneColumnWidth);
      textPainter('Token: $token', tokenColumnRightX, startY,
          align: ui.TextAlign.right, maxWidth: tokenColumnWidth);
      startY += gapY;

      // Booking Date, Expiry Date, Name, Age, Sex, Weight below token
      textPainter('Booking Date: $formattedDate', tokenColumnRightX, startY,
          align: ui.TextAlign.right, maxWidth: tokenColumnWidth);
      startY += gapY;
      textPainter('Expiry Date: $formattedExpiryDate', tokenColumnRightX, startY,
          align: ui.TextAlign.right, maxWidth: tokenColumnWidth);
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

      // 4) Save to temporary file
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/parcha_$token.png');
      await file.writeAsBytes(pngBytes.buffer.asUint8List(), flush: true);

      // 5) Share
      await Share.shareXFiles([XFile(file.path)], text: 'Patient Details');
    } catch (e) {
      onError('Print failed: $e');
    }
  }
}

