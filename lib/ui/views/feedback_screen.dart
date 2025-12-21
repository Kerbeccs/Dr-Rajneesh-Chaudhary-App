import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../viewmodels/feedback_view_model.dart';
import '../../viewmodels/auth_viewmodel.dart';

class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final TextEditingController _commentController = TextEditingController();
  int _selectedRating = 3; // Default to neutral (3 out of 5)
  int _wordCount = 0;

  @override
  void initState() {
    super.initState();
    _commentController.addListener(_updateWordCount);
  }

  @override
  void dispose() {
    _commentController.removeListener(_updateWordCount);
    _commentController.dispose();
    super.dispose();
  }

  void _updateWordCount() {
    setState(() {
      _wordCount = _commentController.text.trim().isEmpty
          ? 0
          : _commentController.text.trim().split(RegExp(r'\s+')).length;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => FeedbackViewModel(),
      child: Consumer<FeedbackViewModel>(
        builder: (context, feedbackViewModel, _) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Submit Feedback'),
            ),
            body: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Emoji Rating
                  const Text(
                    'How was your experience?',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),

                  // Emoji Rating Selector
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildRatingOption(1, '😞', 'Very Bad'),
                        _buildRatingOption(2, '🙁', 'Bad'),
                        _buildRatingOption(3, '😐', 'Okay'),
                        _buildRatingOption(4, '🙂', 'Good'),
                        _buildRatingOption(5, '😃', 'Excellent'),
                      ],
                    ),
                  ),

                  const SizedBox(height: 30),

                  // Comment Field
                  TextField(
                    controller: _commentController,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: 'Your Comments (max 50 words)',
                      hintText: 'Please share your thoughts...',
                      border: const OutlineInputBorder(),
                      counterText: '$_wordCount/50 words',
                      errorText:
                          _wordCount > 50 ? 'Maximum 50 words allowed' : null,
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Submit Button
                  if (feedbackViewModel.isLoading)
                    const Center(child: CircularProgressIndicator())
                  else
                    ElevatedButton(
                      onPressed: _wordCount > 50
                          ? null
                          : () => _submitFeedback(context, feedbackViewModel),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text(
                        'Submit Feedback',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),

                  // Error Message
                  if (feedbackViewModel.errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        feedbackViewModel.errorMessage!,
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
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

  Widget _buildRatingOption(int rating, String emoji, String label) {
    final isSelected = _selectedRating == rating;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedRating = rating;
        });
      },
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isSelected ? Colors.orange.withOpacity(0.2) : null,
              border: isSelected
                  ? Border.all(color: Colors.orange, width: 2)
                  : null,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              emoji,
              style: const TextStyle(fontSize: 30),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? Colors.orange : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submitFeedback(
      BuildContext context, FeedbackViewModel feedbackViewModel) async {
    final authViewModel = Provider.of<AuthViewModel>(context, listen: false);
    final user = authViewModel.currentUser;

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User not found. Please login again.')),
      );
      return;
    }

    final success = await feedbackViewModel.submitFeedback(
      patientId: user.uid,
      patientName: user.patientName,
      comment: _commentController.text.trim(),
      rating: _selectedRating,
    );

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Thank you for your feedback!'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    }
  }
}
