// import 'dart:io';
// import 'package:flutter/foundation.dart';
// import 'package:image_picker/image_picker.dart';
// import 'package:firebase_storage/firebase_storage.dart';
// import 'package:firebase_auth/firebase_auth.dart';
// import 'package:image/image.dart' as img;
// import '../services/database_service.dart';
// import '../models/report_model.dart';
// import '../services/logging_service.dart';
// import 'package:cloud_firestore/cloud_firestore.dart';
// import '../utils/locator.dart'; // Import DI locator

// class ReportViewModel extends ChangeNotifier {
//   // Use dependency injection to get shared service instances
//   // This ensures all ViewModels use the same DatabaseService instance
//   // Benefits: consistent cache, reduced memory, easier testing
//   final DatabaseService _databaseService;
//   final FirebaseStorage _storage;
//   final ImagePicker _picker;
//   final FirebaseFirestore _firestore;

//   // Constructor with optional parameters for testing
//   // If not provided, gets from DI container (locator)
//   ReportViewModel({
//     DatabaseService? databaseService,
//     FirebaseStorage? storage,
//     ImagePicker? picker,
//     FirebaseFirestore? firestore,
//   })  : _databaseService = databaseService ?? locator<DatabaseService>(),
//         _storage = storage ?? locator<FirebaseStorage>(),
//         _picker = picker ?? locator<ImagePicker>(),
//         _firestore = firestore ?? locator<FirebaseFirestore>();

//   bool _isLoading = false;
//   String? _errorMessage;
//   File? _selectedImage;
//   List<ReportModel>? _patientReports;
//   List<Map<String, dynamic>> _reports = [];

//   bool get isLoading => _isLoading;
//   String? get errorMessage => _errorMessage;
//   File? get selectedImage => _selectedImage;
//   List<ReportModel>? get patientReports => _patientReports;
//   List<Map<String, dynamic>> get reports => _reports;

//   Future<void> pickImage(ImageSource source) async {
//     try {
//       final XFile? image = await _picker.pickImage(
//         source: source,
//         imageQuality: 85, // Reduce quality to save space (0-100)
//         maxWidth: 1920, // Max width in pixels
//         maxHeight: 1080, // Max height in pixels
//       );
//       if (image != null) {
//         _selectedImage = File(image.path);
//         notifyListeners();
//       }
//     } catch (e) {
//       _errorMessage = 'Failed to pick image: $e';
//       notifyListeners();
//     }
//   }

//   Future<bool> uploadReport(String patientId, String description) async {
//     if (_selectedImage == null) {
//       _errorMessage = 'Please select an image first';
//       notifyListeners();
//       return false;
//     }

//     try {
//       _isLoading = true;
//       _errorMessage = null;
//       notifyListeners();

//       // Ensure Firebase Auth is available for Storage access
//       if (FirebaseAuth.instance.currentUser == null) {
//         await FirebaseAuth.instance.signInAnonymously();
//       }

//       // Compress image before upload
//       final compressedFile = await _compressImage(_selectedImage!);

//       // Upload image to Firebase Storage with auth UID in path structure
//       final String authUid = FirebaseAuth.instance.currentUser!.uid;
//       final String fileName =
//           'reports/$authUid/${DateTime.now().millisecondsSinceEpoch}.jpg';
//       final ref = _storage.ref().child(fileName);
//       await ref.putFile(compressedFile);
//       final String fileUrl = await ref.getDownloadURL();

//       // Create report with patient's UID
//       final report = ReportModel(
//         reportId: '',
//         patientId: patientId, // Using patient's UID here
//         description: description,
//         fileUrl: fileUrl,
//         uploadedAt: DateTime.now(),
//       );

//       await _databaseService.addReport(report);

//       _selectedImage = null;
//       notifyListeners();
//       return true;
//     } catch (e, st) {
//       LoggingService.error('Error uploading report', e, st);
//       _errorMessage = 'Failed to upload report: $e';
//       notifyListeners();
//       return false;
//     } finally {
//       _isLoading = false;
//       notifyListeners();
//     }
//   }

//   void clearImage() {
//     _selectedImage = null;
//     notifyListeners();
//   }

//   Future<List<ReportModel>> fetchPatientReports(String patientId) async {
//     try {
//       _isLoading = true;
//       _errorMessage = null;
//       notifyListeners();

//       LoggingService.debug('Fetching reports for patient: $patientId');
//       _patientReports = await _databaseService.getPatientReports(patientId);
//       LoggingService.debug('Fetched ${_patientReports?.length} reports');

//       notifyListeners();
//       return _patientReports ?? [];
//     } catch (e, st) {
//       LoggingService.error('Error fetching reports', e, st);
//       _errorMessage = 'Failed to fetch reports: $e';
//       notifyListeners();
//       return [];
//     } finally {
//       _isLoading = false;
//       notifyListeners();
//     }
//   }

//   Future<void> deleteReport(String reportId, String fileUrl) async {
//     try {
//       // First delete the file from Storage if it exists
//       if (fileUrl.isNotEmpty) {
//         try {
//           final storageRef = FirebaseStorage.instance.refFromURL(fileUrl);
//           await storageRef.delete();
//         } catch (e, st) {
//           LoggingService.warning('Error deleting file from storage', e, st);
//         }
//       }

//       // Then delete the document from Firestore
//       await _databaseService.deleteReport(reportId);
//       notifyListeners();
//     } catch (e, st) {
//       LoggingService.error('Error deleting report', e, st);
//       rethrow;
//     }
//   }

//   Future<void> createReport({
//     required String patientId,
//     required String doctorId,
//     required String diagnosis,
//     required String prescription,
//     required String notes,
//   }) async {
//     try {
//       _isLoading = true;
//       notifyListeners();

//       await _firestore.collection('reports').add({
//         'patientId': patientId,
//         'doctorId': doctorId,
//         'diagnosis': diagnosis,
//         'prescription': prescription,
//         'notes': notes,
//         'createdAt': FieldValue.serverTimestamp(),
//       });

//       await fetchPatientReports(patientId);
//     } catch (e) {
//       rethrow;
//     } finally {
//       _isLoading = false;
//       notifyListeners();
//     }
//   }

//   Future<void> fetchPatientReportsFirestore(String patientId) async {
//     try {
//       _isLoading = true;
//       notifyListeners();

//       final snapshot = await _firestore
//           .collection('reports')
//           .where('patientId', isEqualTo: patientId)
//           .get();

//       _reports = snapshot.docs
//           .map((doc) => {
//                 'id': doc.id,
//                 ...doc.data(),
//               })
//           .toList();
//     } catch (e) {
//       rethrow;
//     } finally {
//       _isLoading = false;
//       notifyListeners();
//     }
//   }

//   /// Compresses image to reduce file size
//   Future<File> _compressImage(File imageFile) async {
//     try {
//       // Read the image file
//       final bytes = await imageFile.readAsBytes();
//       final image = img.decodeImage(bytes);

//       if (image == null) {
//         throw Exception('Failed to decode image');
//       }

//       // Resize if too large (max 1200px width/height)
//       img.Image resizedImage = image;
//       if (image.width > 1200 || image.height > 1200) {
//         resizedImage = img.copyResize(
//           image,
//           width: image.width > image.height ? 1200 : null,
//           height: image.height > image.width ? 1200 : null,
//           maintainAspect: true,
//         );
//       }

//       // Create compressed JPEG with quality 80%
//       final compressedBytes = Uint8List.fromList(
//         img.encodeJpg(resizedImage, quality: 80),
//       );

//       // Save to temporary file
//       final tempDir = Directory.systemTemp;
//       final tempFile = File(
//           '${tempDir.path}/compressed_${DateTime.now().millisecondsSinceEpoch}.jpg');
//       await tempFile.writeAsBytes(compressedBytes);

//       LoggingService.debug('Original size: ${bytes.length} bytes');
//       LoggingService.debug('Compressed size: ${compressedBytes.length} bytes');
//       LoggingService.debug(
//           'Compression ratio: ${((bytes.length - compressedBytes.length) / bytes.length * 100).toStringAsFixed(1)}%');

//       return tempFile;
//     } catch (e, st) {
//       LoggingService.error('Error compressing image', e, st);
//       // Return original file if compression fails
//       return imageFile;
//     }
//   }
// }
