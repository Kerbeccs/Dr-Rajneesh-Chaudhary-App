import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io' if (dart.library.html) 'package:test_app/utils/file_stub.dart' show File;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:share_plus/share_plus.dart';

class CompounderPatientsListScreen extends StatefulWidget {
  const CompounderPatientsListScreen({super.key});

  @override
  State<CompounderPatientsListScreen> createState() =>
      _CompounderPatientsListScreenState();
}

class _CompounderPatientsListScreenState
    extends State<CompounderPatientsListScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _printAppointmentCard(Map<String, dynamic> appt) async {
    try {
      final tokenId = appt['patientToken'] as String?;
      if (tokenId == null || tokenId.isEmpty) {
        _showSnack('Missing token id');
        return;
      }

      // 1) Load patient details by tokenId from 'patients'
      final patSnap = await FirebaseFirestore.instance
          .collection('patients')
          .where('tokenId', isEqualTo: tokenId)
          .limit(1)
          .get();
      if (patSnap.docs.isEmpty) {
        _showSnack('Patient record not found');
        return;
      }
      final p = patSnap.docs.first.data();

      final name = (p['name'] ?? '').toString();
      final age = (p['age'] ?? '').toString();
      final weight = (p['weightKg'] ?? '').toString();
      final sex = (p['sex'] ?? '').toString();
      final phone = (p['mobileNumber'] ?? '').toString();
      final token = (p['tokenId'] ?? '').toString();
      final aadhaar = (p['aadhaarLast4'] ?? '').toString();

      // 2) Load base image from assets
      final byteData = await rootBundle.load('assets/logos/parcha.jpg');
      final Uint8List bytes = byteData.buffer.asUint8List();
      final ui.Codec codec = await ui.instantiateImageCodec(bytes);
      final ui.FrameInfo frame = await codec.getNextFrame();
      final ui.Image baseImage = frame.image;

      // 3) Draw text onto the image
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final ui.Canvas canvas = ui.Canvas(recorder);
      final paint = ui.Paint();
      // Draw the base image first
      canvas.drawImage(baseImage, const ui.Offset(0, 0), paint);

      textPainter(String text, double x, double y,
          {double fontSize = 28, ui.Color color = const ui.Color(0xFF000000)}) {
        final ui.ParagraphBuilder builder = ui.ParagraphBuilder(
          ui.ParagraphStyle(
            textAlign: TextAlign.left,
            fontSize: fontSize,
            maxLines: 1,
          ),
        )
          ..pushStyle(ui.TextStyle(color: color))
          ..addText(text);
        final ui.Paragraph paragraph = builder.build()
          ..layout(const ui.ParagraphConstraints(width: double.infinity));
        canvas.drawParagraph(paragraph, ui.Offset(x, y));
      }

      // Positioning: tweak Y values to align nicely on your parcha
      double startY = 80; // top padding
      const double startX = 40; // left padding
      const double gapY = 44; // vertical gap between lines

      // Shift content down by 5 lines
      startY += gapY * 7;

      textPainter('Token: $token', startX, startY);
      startY += gapY;
      textPainter('Name: $name', startX, startY);
      startY += gapY;
      textPainter('Age: $age', startX, startY);
      startY += gapY;
      textPainter('Weight: $weight', startX, startY);
      startY += gapY;
      textPainter('Sex: $sex', startX, startY);
      startY += gapY;
      textPainter('Aadhaar: $aadhaar', startX, startY);
      startY += gapY;
      textPainter('Phone: $phone', startX, startY);

      final ui.Picture picture = recorder.endRecording();
      final ui.Image finalImage = await picture.toImage(
        baseImage.width,
        baseImage.height,
      );
      final ByteData? pngBytes =
          await finalImage.toByteData(format: ui.ImageByteFormat.png);
      if (pngBytes == null) {
        _showSnack('Failed to compose image');
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
        final file = File('${dir.path}/parcha_$token.png');
        await file.writeAsBytes(imageBytes, flush: true);
        await Share.shareXFiles([XFile(file.path)], text: 'Patient Details');
      }
    } catch (e) {
      _showSnack('Print failed: $e');
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Stream<List<Map<String, dynamic>>> _todayAppointmentsStream() {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return FirebaseFirestore.instance
        .collection('appointments')
        .where('appointmentDate', isEqualTo: today)
        .snapshots()
        .map((q) {
      final list = q.docs.map((d) => d.data()).toList();
      // Sort by createdAt in memory to avoid Firestore index requirement
      list.sort((a, b) {
        final aTime = a['createdAt'] as Timestamp?;
        final bTime = b['createdAt'] as Timestamp?;
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime); // Descending order
      });
      return list;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Today\'s Patients')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Search by Token ID',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: _todayAppointmentsStream(),
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final list = snap.data ?? [];
                  final q = _searchController.text.trim().toLowerCase();
                  final filtered = q.isEmpty
                      ? list
                      : list
                          .where((e) => (e['patientToken'] ?? '')
                              .toString()
                              .toLowerCase()
                              .contains(q))
                          .toList();
                  if (filtered.isEmpty) {
                    return const Center(child: Text('No patients found.'));
                  }
                  return ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 16),
                    itemBuilder: (context, idx) {
                      final e = filtered[idx];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.blue.shade100,
                          child: const Icon(Icons.tag, color: Colors.blue),
                        ),
                        title: Text(e['patientToken'] ?? ''),
                        subtitle: Text(
                            '${e['patientName'] ?? ''} • Seat ${e['seatNumber'] ?? ''} • ${e['appointmentTime'] ?? ''}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.print, color: Colors.blue),
                          onPressed: () => _printAppointmentCard(e),
                          tooltip: 'Print Patient Details',
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
