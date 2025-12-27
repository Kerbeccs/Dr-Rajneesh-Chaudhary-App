import 'package:flutter/material.dart';
import '../../services/database_service.dart';
import '../../models/patient_record.dart';
import 'package:intl/intl.dart';
import '../../utils/locator.dart'; // Import DI locator

class PatientRecordsScreen extends StatefulWidget {
  const PatientRecordsScreen({super.key});

  @override
  State<PatientRecordsScreen> createState() => _PatientRecordsScreenState();
}

class _PatientRecordsScreenState extends State<PatientRecordsScreen> {
  // Use dependency injection to get shared DatabaseService instance
  final DatabaseService _databaseService = locator<DatabaseService>();
  String searchQuery = '';
  List<PatientRecord> allPatients = [];
  List<PatientRecord> filteredPatients = [];
  bool isLoading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _loadPatients();
  }

  Future<void> _loadPatients() async {
    try {
      setState(() {
        isLoading = true;
        error = null;
      });

      final patients =
          await _databaseService.getAllPatientsForDoctorDashboard();
      setState(() {
        allPatients = patients;
        filteredPatients = patients;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        error = 'Failed to load patients: $e';
        isLoading = false;
      });
    }
  }

  void _filterPatients(String query) {
    setState(() {
      searchQuery = query;
      filteredPatients = allPatients.where((patient) {
        return patient.name.toLowerCase().contains(query.toLowerCase()) ||
            patient.mobileNumber.toLowerCase().contains(query.toLowerCase()) ||
            patient.tokenId.toLowerCase().contains(query.toLowerCase());
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Patient Records'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              onChanged: _filterPatients,
              decoration: InputDecoration(
                labelText: 'Search Patients (name, mobile, token)',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : error != null
                    ? Center(
                        child: Text(error!,
                            style: const TextStyle(color: Colors.red)))
                    : filteredPatients.isEmpty
                        ? const Center(child: Text('No patients found'))
                        : ListView.builder(
                            itemCount: filteredPatients.length,
                            itemBuilder: (context, index) {
                              final patient = filteredPatients[index];
                              return Card(
                                margin: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    child: Text(patient.name.isNotEmpty
                                        ? patient.name[0].toUpperCase()
                                        : '?'),
                                  ),
                                  title: Text(patient.name),
                                  subtitle: Text(
                                      'Token: ${patient.tokenId} | Mobile: ${patient.mobileNumber}'),
                                  trailing: const Icon(Icons.arrow_forward_ios),
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            PatientDetailsScreen(
                                                patient: patient),
                                      ),
                                    );
                                  },
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

class PatientDetailsScreen extends StatefulWidget {
  final PatientRecord patient;

  const PatientDetailsScreen({super.key, required this.patient});

  @override
  State<PatientDetailsScreen> createState() => _PatientDetailsScreenState();
}

class _PatientDetailsScreenState extends State<PatientDetailsScreen> {
  // Use dependency injection to get shared DatabaseService instance
  final DatabaseService _databaseService = locator<DatabaseService>();
  late PatientRecord _patient;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _patient = widget.patient;
  }

  Future<void> _refreshPatientData() async {
    try {
      setState(() {
        _isRefreshing = true;
      });

      // Fetch the latest patient data by token
      final updated =
          await _databaseService.getPatientByToken(_patient.tokenId);
      if (updated != null) {
        setState(() {
          _patient = updated;
        });
      }
    } catch (e) {
      print('Error refreshing patient data: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to refresh data: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isRefreshing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_patient.name),
      ),
      body: _isRefreshing
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Patient Information',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const Divider(),
                          _buildInfoRow('Name', _patient.name),
                          _buildInfoRow('Token ID', _patient.tokenId),
                          _buildInfoRow('Mobile', _patient.mobileNumber),
                          _buildInfoRow('Age', '${_patient.age} years'),
                          _buildInfoRow(
                              'Aadhaar Last 4', _patient.aadhaarLast4),
                          if (_patient.lastVisited != null)
                            _buildInfoRow(
                              'Last Fee Paid',
                              DateFormat('yyyy-MM-dd HH:mm')
                                  .format(_patient.lastVisited!),
                            ),
                          _buildInfoRow(
                              'Created',
                              DateFormat('yyyy-MM-dd HH:mm')
                                  .format(_patient.createdAt)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _refreshPatientData,
        child: const Icon(Icons.refresh),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
