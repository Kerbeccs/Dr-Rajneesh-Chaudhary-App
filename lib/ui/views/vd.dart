import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../viewmodels/report_view_model.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../models/report_model.dart';
import 'package:firebase_storage/firebase_storage.dart';

class ViewDeleteReports extends StatefulWidget {
  const ViewDeleteReports({super.key});

  @override
  State<ViewDeleteReports> createState() => _ViewDeleteReportsState();
}

class _ViewDeleteReportsState extends State<ViewDeleteReports> {
  Future<List<ReportModel>>? _reportsFuture;

  @override
  void initState() {
    super.initState();
    _initReportsFuture();
  }

  void _initReportsFuture() async {
    final authViewModel = Provider.of<AuthViewModel>(context, listen: false);
    final user = await authViewModel.getCurrentUser();
    if (user != null) {
      setState(() {
        _reportsFuture = Provider.of<ReportViewModel>(context, listen: false)
            .fetchPatientReports(user.uid);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Reports'),
      ),
      body: _reportsFuture == null
          ? const Center(child: Text('No user logged in'))
          : FutureBuilder<List<ReportModel>>(
              future: _reportsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                      child: Text('Error loading reports: ${snapshot.error}'));
                }

                final reports = snapshot.data ?? [];
                if (reports.isEmpty) {
                  return const Center(child: Text('No reports found'));
                }

                return ListView.builder(
                  itemCount: reports.length,
                  itemBuilder: (context, index) {
                    final report = reports[index];
                    return Card(
                      margin: const EdgeInsets.all(8.0),
                      child: ListTile(
                        leading: report.fileUrl.toLowerCase().endsWith('.pdf')
                            ? const Icon(Icons.picture_as_pdf)
                            : Image.network(
                                report.fileUrl,
                                width: 50,
                                height: 50,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    const Icon(Icons.error),
                              ),
                        title: Text('Report ${index + 1}'),
                        subtitle: Text(
                            'Uploaded: ${report.uploadedAt.toString()}\n${report.description}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.visibility,
                                  color: Colors.blue),
                              onPressed: () => _viewReport(context, report),
                              tooltip: 'View Report',
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () =>
                                  _showDeleteConfirmation(context, report),
                              tooltip: 'Delete Report',
                            ),
                          ],
                        ),
                        onTap: () => _viewReport(context, report),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }

  void _viewReport(BuildContext context, ReportModel report) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _ReportViewerScreen(report: report),
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context, ReportModel report) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Report'),
        content: const Text('Are you sure you want to delete this report?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteReport(context, report);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteReport(BuildContext context, ReportModel report) async {
    try {
      final reportViewModel =
          Provider.of<ReportViewModel>(context, listen: false);

      // Show loading indicator
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Deleting report...')),
      );

      // Delete from Storage first
      if (report.fileUrl.isNotEmpty) {
        try {
          final storageRef =
              FirebaseStorage.instance.refFromURL(report.fileUrl);
          await storageRef.delete();
        } catch (e) {
          print('Storage deletion error: $e');
          // Continue with Firestore deletion even if storage deletion fails
        }
      }

      // Delete from Firestore
      await reportViewModel.deleteReport(report.reportId, report.patientId);

      // Refresh the reports list
      setState(() {
        _initReportsFuture();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Report deleted successfully')),
      );
    } catch (e) {
      print('Delete error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error deleting report: $e')),
      );
    }
  }
}

// Full-screen image viewer for reports
class _ReportViewerScreen extends StatelessWidget {
  final ReportModel report;

  const _ReportViewerScreen({required this.report});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Report Viewer'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () => _shareReport(context),
            tooltip: 'Share Report',
          ),
        ],
      ),
      body: Column(
        children: [
          // Report details
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Colors.grey[100],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Description: ${report.description}',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Uploaded: ${report.uploadedAt.toString().split('.')[0]}',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          // Image viewer
          Expanded(
            child: Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: Image.network(
                  report.fileUrl,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          Text(
                            'Loading report...',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            size: 64,
                            color: Colors.red,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Failed to load report',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.red,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Error: $error',
                            style: TextStyle(color: Colors.grey[600]),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Go Back'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _shareReport(BuildContext context) {
    // You can implement sharing functionality here if needed
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Share functionality can be added here')),
    );
  }
}
