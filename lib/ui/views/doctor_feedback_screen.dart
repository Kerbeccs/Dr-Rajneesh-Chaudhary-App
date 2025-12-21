import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../viewmodels/feedback_view_model.dart';
import '../../models/feedback_model.dart';

class DoctorFeedbackScreen extends StatefulWidget {
  const DoctorFeedbackScreen({super.key});

  @override
  State<DoctorFeedbackScreen> createState() => _DoctorFeedbackScreenState();
}

class _DoctorFeedbackScreenState extends State<DoctorFeedbackScreen> {
  @override
  void initState() {
    super.initState();
    // Fetch active feedback when screen loads
    Future.microtask(() =>
        Provider.of<FeedbackViewModel>(context, listen: false)
            .fetchActiveFeedback());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Patient Feedback'),
      ),
      body: Consumer<FeedbackViewModel>(
        builder: (context, viewModel, _) {
          if (viewModel.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (viewModel.errorMessage != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 60,
                    color: Colors.red,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Error: ${viewModel.errorMessage}',
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => viewModel.fetchActiveFeedback(),
                    child: const Text('Try Again'),
                  ),
                ],
              ),
            );
          }

          if (viewModel.feedbackList.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.forum_outlined,
                    size: 80,
                    color: Colors.grey,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'No feedback to display',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'You\'ll see feedback from patients here once they submit it.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => viewModel.fetchActiveFeedback(),
            child: ListView.builder(
              padding: const EdgeInsets.all(16.0),
              itemCount: viewModel.feedbackList.length,
              itemBuilder: (context, index) {
                final feedback = viewModel.feedbackList[index];
                return _buildFeedbackCard(context, feedback);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildFeedbackCard(BuildContext context, FeedbackModel feedback) {
    // Get emoji for rating
    final String emoji = _getEmojiForRating(feedback.rating);

    // Format date
    final formattedDate = DateFormat('MMM d, yyyy').format(feedback.createdAt);
    final daysLeft = 7 - DateTime.now().difference(feedback.createdAt).inDays;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with rating and patient name
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: _getColorForRating(feedback.rating),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      emoji,
                      style: const TextStyle(fontSize: 24),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        feedback.patientName,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                      ),
                      Text(
                        'Rating: ${feedback.rating}/5',
                        style: TextStyle(
                          color: _getColorForRating(feedback.rating),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const Divider(height: 24),

            // Comment
            if (feedback.comment.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  '"${feedback.comment}"',
                  style: const TextStyle(
                    fontSize: 16,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),

            // Footer with date and expiry info
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  formattedDate,
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                  ),
                ),
                Text(
                  'Expires in $daysLeft days',
                  style: const TextStyle(
                    color: Colors.orange,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _getEmojiForRating(int rating) {
    switch (rating) {
      case 1:
        return '😞';
      case 2:
        return '🙁';
      case 3:
        return '😐';
      case 4:
        return '🙂';
      case 5:
        return '😃';
      default:
        return '😐';
    }
  }

  Color _getColorForRating(int rating) {
    switch (rating) {
      case 1:
        return Colors.red.shade200;
      case 2:
        return Colors.orange.shade200;
      case 3:
        return Colors.yellow.shade200;
      case 4:
        return Colors.lightGreen.shade200;
      case 5:
        return Colors.green.shade200;
      default:
        return Colors.yellow.shade200;
    }
  }
}
