import 'package:flutter/foundation.dart';
import '../services/database_service.dart';
import '../models/feedback_model.dart';
import '../utils/locator.dart'; // Import DI locator

class FeedbackViewModel extends ChangeNotifier {
  // Use dependency injection to get shared DatabaseService instance
  // This ensures consistent data access across the app
  final DatabaseService _databaseService;
  
  // Constructor with optional parameter for testing
  FeedbackViewModel({DatabaseService? databaseService})
      : _databaseService = databaseService ?? locator<DatabaseService>();

  bool _isLoading = false;
  String? _errorMessage;
  List<FeedbackModel> _feedbackList = [];

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<FeedbackModel> get feedbackList => _feedbackList;

  Future<bool> submitFeedback({
    required String patientId,
    required String patientName,
    required String comment,
    required int rating,
  }) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      // Validate comment length (max 50 words)
      final wordCount = comment.trim().split(RegExp(r'\s+')).length;
      if (wordCount > 50) {
        _errorMessage = 'Comment must be 50 words or less';
        return false;
      }

      // Create feedback model
      final feedback = FeedbackModel(
        id: '', // Will be set by the database service
        patientId: patientId,
        patientName: patientName,
        comment: comment,
        rating: rating,
        createdAt: DateTime.now(),
      );

      // Add to database
      await _databaseService.addFeedback(feedback);

      return true;
    } catch (e) {
      _errorMessage = 'Failed to submit feedback: $e';
      print('Error submitting feedback: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchActiveFeedback() async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      _feedbackList = await _databaseService.getActiveFeedback();
    } catch (e) {
      _errorMessage = 'Failed to load feedback: $e';
      print('Error loading feedback: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
