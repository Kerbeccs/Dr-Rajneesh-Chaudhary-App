import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../../viewmodels/auth_viewmodel.dart';
import '../views/booking_screen.dart';
import '../views/upload_report_screen.dart';
import '../../viewmodels/ticket_view_model.dart';
import '../../models/user_model.dart';
import '../views/vd.dart';
import '../views/edit_profile_screen.dart';
import '../views/feedback_screen.dart';
import '../../viewmodels/patient_appointment_status_view_model.dart';
import '../views/ticket_details_screen.dart';
import '../../viewmodels/booking_view_model.dart';
import '../../models/patient_record.dart';
import '../../services/token_cache_service.dart';

class PatientDashboard extends StatefulWidget {
  const PatientDashboard({super.key});

  @override
  State<PatientDashboard> createState() => _PatientDashboardState();
}

class _PatientDashboardState extends State<PatientDashboard> {
  final GlobalKey<_TokenIdListCardState> _tokenListKey =
      GlobalKey<_TokenIdListCardState>();
  @override
  void initState() {
    super.initState();
    // Ensure user data is loaded
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authViewModel = Provider.of<AuthViewModel>(context, listen: false);
      if (authViewModel.currentUser == null) {
        authViewModel.loadUserData();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final authViewModel = Provider.of<AuthViewModel>(context);
    final user = authViewModel.currentUser;

    if (authViewModel.isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (user == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Error loading user data'),
              ElevatedButton(
                onPressed: () {
                  authViewModel.signOut();
                  Navigator.pushReplacementNamed(context, '/login');
                },
                child: const Text('Back to Login'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Welcome, ${user.patientName}'),
        actions: [
          IconButton(
            tooltip: 'Refresh Token IDs',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _tokenListKey.currentState?.manualRefresh();
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await authViewModel.signOut();
              if (mounted) {
                Navigator.pushReplacementNamed(context, '/login');
              }
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _DashboardImage(),
            const _MenuGrid(),
            _TokenIdListCard(key: _tokenListKey),
          ],
        ),
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
            width: 100,
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

// Separate widget for the image to prevent rebuilds
class _DashboardImage extends StatelessWidget {
  const _DashboardImage();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/logos/splash.png',
      height: 200,
      width: double.infinity,
      fit: BoxFit.contain,
      cacheWidth: (MediaQuery.of(context).size.width * 2)
          .toInt(), // Optimize image size
    );
  }
}

// Separate widget for the appointment status card
class _AppointmentStatusCard extends StatelessWidget {
  const _AppointmentStatusCard();

  @override
  Widget build(BuildContext context) {
    return Consumer<PatientAppointmentStatusViewModel>(
      builder: (context, patientStatusViewModel, child) {
        // Resume the ViewModel when the widget is built
        WidgetsBinding.instance.addPostFrameCallback((_) {
          patientStatusViewModel.resume();
        });

        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your Appointment Status:',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 10),
                  if (patientStatusViewModel.isLoading)
                    const Center(child: CircularProgressIndicator())
                  else if (patientStatusViewModel.errorMessage != null)
                    Text(
                      patientStatusViewModel.errorMessage!,
                      style: const TextStyle(color: Colors.red),
                    )
                  else
                    Text(
                      patientStatusViewModel.waitingStatus,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  if (patientStatusViewModel.patientAppointment != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Appointment Time: ${patientStatusViewModel.patientAppointment!['appointmentTime'] ?? 'Not specified'}',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Date: ${patientStatusViewModel.patientAppointment!['appointmentDate'] ?? 'Not specified'}',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// Separate widget for the menu grid
class _MenuGrid extends StatelessWidget {
  const _MenuGrid();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        mainAxisSpacing: 20,
        crossAxisSpacing: 20,
        children: [
          _MenuCard(
            title: 'Upload Report',
            icon: Icons.upload_file,
            color: Colors.blue,
            route: UploadReportScreen(),
          ),
          const _MenuCard(
            title: 'View Report',
            icon: Icons.upload_file_rounded,
            color: Color.fromARGB(255, 9, 114, 125),
            route: ViewDeleteReports(),
          ),
          _MenuCard(
            title: 'Book Appointment',
            icon: Icons.calendar_today,
            color: Colors.green,
            route: MultiProvider(
              providers: [
                ChangeNotifierProvider(create: (_) => BookingViewModel()),
                ChangeNotifierProvider.value(
                    value: Provider.of<AuthViewModel>(context, listen: false)),
              ],
              child: const BookingScreen(),
            ),
          ),
          const _MenuCard(
            title: 'Feedback',
            icon: Icons.feedback,
            color: Colors.orange,
            route: FeedbackScreen(),
          ),
          const _MenuCard(
            title: 'Edit Profile',
            icon: Icons.person_outline,
            color: Colors.purple,
            route: EditProfileScreen(),
          ),
          const _TicketMenuCard(),
        ],
      ),
    );
  }
}

// Separate widget for menu cards
class _MenuCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final Widget route;

  const _MenuCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.route,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
      ),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => route),
          );
        },
        borderRadius: BorderRadius.circular(15),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withOpacity(0.7),
                color,
              ],
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 50,
                color: Colors.white,
              ),
              const SizedBox(height: 10),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Separate widget for the ticket menu card
class _TicketMenuCard extends StatelessWidget {
  const _TicketMenuCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
      ),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => FutureBuilder<UserModel?>(
                future: context.read<AuthViewModel>().getCurrentUser(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Scaffold(
                      body: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final user = snapshot.data;
                  if (user == null) {
                    return const Scaffold(
                      body: Center(child: Text('No user data available')),
                    );
                  }
                  return ChangeNotifierProvider(
                    create: (_) => TicketViewModel(userId: user.uid),
                    child: const TicketDetailsScreen(),
                  );
                },
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(15),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.amber.withOpacity(0.7),
                Colors.amber,
              ],
            ),
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.confirmation_number_outlined,
                size: 50,
                color: Colors.white,
              ),
              SizedBox(height: 10),
              Text(
                'View Ticket',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Token Id list widget (fetches from 'patients' collection)
class _TokenIdListCard extends StatefulWidget {
  const _TokenIdListCard({super.key});

  @override
  State<_TokenIdListCard> createState() => _TokenIdListCardState();
}

class _TokenIdListCardState extends State<_TokenIdListCard> {
  List<PatientRecord>? _cachedRecords;
  bool _isRefreshing = false;
  String? _currentPhone;

  @override
  void initState() {
    super.initState();
    _loadCachedData();
  }

  /// Load cached token IDs when widget initializes
  Future<void> _loadCachedData() async {
    final phone = context.read<AuthViewModel>().currentUser?.phoneNumber;
    if (phone != null) {
      _currentPhone = phone;
      final cached = await TokenCacheService.getCachedTokenIds(phone);
      if (cached != null && mounted) {
        setState(() {
          _cachedRecords = cached;
        });
      }
    }
  }

  /// Manual refresh - fetches fresh data from Firestore
  Future<void> manualRefresh() async {
    if (_isRefreshing) return; // Prevent multiple simultaneous refreshes

    setState(() {
      _isRefreshing = true;
    });

    try {
      final phone = context.read<AuthViewModel>().currentUser?.phoneNumber;
      if (phone != null) {
        _currentPhone = phone;
        // Force refresh by clearing cache and reloading
        await TokenCacheService.clearCache(phone);
        await _loadCachedData();
        // Trigger stream to fetch fresh data
        setState(() {
          _cachedRecords = null; // Clear cache to force fresh fetch
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  Stream<List<PatientRecord>> _patientsStreamFilteredByPhone(String? phone) {
    if (phone == null || phone.isEmpty) {
      // Return empty stream if we cannot identify the user's phone number
      return const Stream<List<PatientRecord>>.empty();
    }

    // Build candidate phone variants to handle stored formats like '+9180...' vs '8081...'
    final variants = _buildPhoneVariants(phone);

    // Query 1: Match by userPhoneNumber (logged-in user who created the booking)
    final userPhoneStream = FirebaseFirestore.instance
        .collection('patients')
        .where('userPhoneNumber', whereIn: variants)
        .snapshots()
        .map(
            (q) => q.docs.map((d) => PatientRecord.fromMap(d.data())).toList());

    // Query 2: Match by mobileNumber (patient's own phone number)
    final mobileNumberStream = FirebaseFirestore.instance
        .collection('patients')
        .where('mobileNumber', whereIn: variants)
        .snapshots()
        .map(
            (q) => q.docs.map((d) => PatientRecord.fromMap(d.data())).toList());

    // Combine both streams and remove duplicates based on tokenId
    // Using StreamController to merge the two streams
    final controller = StreamController<List<PatientRecord>>();
    final allRecords = <String, PatientRecord>{};
    StreamSubscription? sub1;
    StreamSubscription? sub2;

    void emitCombined() {
      final sortedList = allRecords.values.toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (!controller.isClosed) {
        controller.add(sortedList);
        // Cache the results for future use
        if (sortedList.isNotEmpty) {
          TokenCacheService.cacheTokenIds(phone, sortedList);
        }
      }
    }

    // Listen to userPhoneNumber stream
    sub1 = userPhoneStream.listen((records) {
      for (var record in records) {
        allRecords[record.tokenId] = record;
      }
      emitCombined();
    }, onError: (error) {
      if (!controller.isClosed) {
        controller.addError(error);
      }
    });

    // Listen to mobileNumber stream
    sub2 = mobileNumberStream.listen((records) {
      for (var record in records) {
        allRecords[record.tokenId] = record;
      }
      emitCombined();
    }, onError: (error) {
      if (!controller.isClosed) {
        controller.addError(error);
      }
    });

    // Clean up subscriptions when stream is cancelled
    controller.onCancel = () {
      sub1?.cancel();
      sub2?.cancel();
    };

    return controller.stream;
  }

  List<String> _buildPhoneVariants(String raw) {
    String trimmed = raw.trim();
    // Keep original as-is
    final Set<String> out = {trimmed};

    // Strip non-digits except leading '+'
    final onlyDigits = trimmed.replaceAll(RegExp(r"[^0-9+]"), '');
    out.add(onlyDigits);

    // Remove '+' for digit-only processing
    final digits =
        onlyDigits.startsWith('+') ? onlyDigits.substring(1) : onlyDigits;

    // If number has leading 0 and total 11, also add last 10
    if (digits.length == 11 && digits.startsWith('0')) {
      out.add(digits.substring(1));
    }

    // If 10-digit local number, add '+91' prefixed version
    if (digits.length == 10) {
      out.add('+91$digits');
      out.add('91$digits');
    }

    // If begins with '91' and total 12, add '+91' prefixed
    if (digits.length == 12 && digits.startsWith('91')) {
      out.add('+$digits');
      out.add(digits.substring(2)); // also local 10-digit
    }

    // If already starts with '+', add without plus variant
    if (onlyDigits.startsWith('+')) {
      out.add(onlyDigits.substring(1));
    } else {
      // Add '+' variant
      out.add('+$onlyDigits');
    }

    // Firestore whereIn max 10; keep first up to 10
    return out.where((s) => s.isNotEmpty).take(10).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Token Ids',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Refresh',
                    icon: _isRefreshing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                    onPressed: _isRefreshing ? null : manualRefresh,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Show cached data immediately, then update from stream
              Builder(
                builder: (context) {
                  final phone = context.read<AuthViewModel>().currentUser?.phoneNumber;
                  
                  // If we have cached data and not refreshing, show it immediately
                  if (_cachedRecords != null && !_isRefreshing) {
                    return StreamBuilder<List<PatientRecord>>(
                      stream: _patientsStreamFilteredByPhone(phone),
                      initialData: _cachedRecords, // Show cached data first
                      builder: (context, snapshot) {
                        final records = snapshot.data ?? _cachedRecords ?? [];
                        if (records.isEmpty) {
                          return const Text('No tokens found.');
                        }
                        return ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: records.length,
                          separatorBuilder: (_, __) => const Divider(height: 16),
                          itemBuilder: (context, index) {
                            final r = records[index];
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                backgroundColor: Colors.blue.shade100,
                                child: const Icon(Icons.tag, color: Colors.blue),
                              ),
                              title: Text(r.tokenId),
                              subtitle: Text('${r.name} • ${r.mobileNumber}'),
                            );
                          },
                        );
                      },
                    );
                  }

                  // No cache or refreshing - show loading or stream data
                  return StreamBuilder<List<PatientRecord>>(
                    stream: _patientsStreamFilteredByPhone(phone),
                    builder: (context, snapshot) {
                      if (_isRefreshing) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Column(
                              children: [
                                CircularProgressIndicator(),
                                SizedBox(height: 8),
                                Text('Refreshing...'),
                              ],
                            ),
                          ),
                        );
                      }

                      if (snapshot.connectionState == ConnectionState.waiting &&
                          _cachedRecords == null) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final records = snapshot.data ?? _cachedRecords ?? [];
                      if (records.isEmpty) {
                        return const Text('No tokens found.');
                      }
                      return ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: records.length,
                        separatorBuilder: (_, __) => const Divider(height: 16),
                        itemBuilder: (context, index) {
                          final r = records[index];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              backgroundColor: Colors.blue.shade100,
                              child: const Icon(Icons.tag, color: Colors.blue),
                            ),
                            title: Text(r.tokenId),
                            subtitle: Text('${r.name} • ${r.mobileNumber}'),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
