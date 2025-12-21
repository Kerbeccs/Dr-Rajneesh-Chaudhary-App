import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../../viewmodels/report_view_model.dart';
import '../../viewmodels/auth_viewmodel.dart';

class UploadReportScreen extends StatelessWidget {
  final TextEditingController descriptionController = TextEditingController();

  UploadReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ReportViewModel(),
      child: Consumer<ReportViewModel>(
        builder: (context, reportViewModel, child) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Upload Report'),
            ),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (reportViewModel.selectedImage != null) ...[
                    Image.file(
                      reportViewModel.selectedImage!,
                      height: 200,
                      fit: BoxFit.cover,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: reportViewModel.clearImage,
                      child: const Text('Remove Image'),
                    ),
                  ] else ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () =>
                              reportViewModel.pickImage(ImageSource.camera),
                          icon: const Icon(Icons.camera_alt),
                          label: const Text('Take Photo'),
                        ),
                        ElevatedButton.icon(
                          onPressed: () =>
                              reportViewModel.pickImage(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library),
                          label: const Text('Choose from Gallery'),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextField(
                    controller: descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),
                  if (reportViewModel.isLoading)
                    const Center(child: CircularProgressIndicator())
                  else
                    ElevatedButton(
                      onPressed: () async {
                        final authViewModel = context.read<AuthViewModel>();
                        final user = authViewModel.currentUser;
                        if (user == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('No user data available')),
                          );
                          return;
                        }
                        final success = await reportViewModel.uploadReport(
                          user.uid,
                          descriptionController.text,
                        );
                        if (success) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Report uploaded successfully')),
                          );
                        }
                      },
                      child: const Text('Upload Report'),
                    ),
                  if (reportViewModel.errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        reportViewModel.errorMessage!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
