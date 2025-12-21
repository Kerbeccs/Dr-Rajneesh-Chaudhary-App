// Using debugPrint for logging

class AppointmentEstimator {
  /// Estimates the waiting time for a specific patient.
  ///
  /// Args:
  ///   patientAppointmentId: The ID of the appointment for the patient we want to estimate the waiting time.
  ///   allAppointments: A list of all appointments for the day, sorted by time.
  ///   sessionStartTime: The DateTime when the doctor's session started.
  ///   isSessionPaused: A boolean indicating if the doctor's session is currently paused.
  ///   sessionPauseTime: The DateTime when the doctor's session was paused (if paused).
  ///   totalBreakTime: The total Duration the doctor has been on break.
  ///   averageConsultationTime: The average time spent per consultation in minutes.
  ///
  /// Returns: A String message estimating the waiting time or the current status.
  String estimateWaitingTime({
    required String patientAppointmentId,
    required List<Map<String, dynamic>> allAppointments,
    required DateTime? sessionStartTime,
    required bool isSessionPaused,
    required DateTime? sessionPauseTime,
    required Duration totalBreakTime,
    required int averageConsultationTime,
  }) {
    if (sessionStartTime == null) {
      return "Doctor session hasn't started yet.";
    }

    if (isSessionPaused) {
      return "Doctor on break. Waiting time will be updated when session resumes.";
    }

    final now = DateTime.now();
    Duration activeSessionDuration = now.difference(sessionStartTime);

    // Subtract any accumulated break time
    activeSessionDuration -= totalBreakTime;

    // Find the target patient's position and status
    int patientIndex = allAppointments
        .indexWhere((appt) => appt['appointmentId'] == patientAppointmentId);

    if (patientIndex == -1) {
      return "Your appointment not found.";
    }

    final patientAppointment = allAppointments[patientIndex];
    final patientStatus = patientAppointment['status'];

    if (patientStatus == 'in_progress') {
      return "You are currently in consultation.";
    }

    if (patientStatus == 'completed') {
      return "Your consultation is completed.";
    }

    // Count completed or in-progress appointments before the patient
    int completedOrInProgressCount = 0;
    for (int i = 0; i <= patientIndex; i++) {
      final status = allAppointments[i]['status'];
      if (status == 'completed' || status == 'in_progress') {
        completedOrInProgressCount++;
      }
    }

    // Estimate time spent on appointments before the patient
    // We assume that 'in_progress' is the current one and count previous completed ones.
    // If the target patient is the first pending after completed ones, consider time spent so far.
    Duration estimatedTimeSpent =
        Duration(minutes: completedOrInProgressCount * averageConsultationTime);

    // If estimated time spent is less than actual active session duration, use active session duration
    // This accounts for variability in earlier appointments
    if (estimatedTimeSpent < activeSessionDuration) {
      // Adjust estimated time spent based on actual time, but only up to the current patient's position
      Duration timeSpentOnPrevious = Duration.zero;
      for (int i = 0; i < patientIndex; i++) {
        final status = allAppointments[i]['status'];
        if (status == 'completed') {
          // If we tracked actual consultation time, use it here
          // For now, using average as actual time isn't stored per completed appt in this flow
          timeSpentOnPrevious += Duration(minutes: averageConsultationTime);
        } else if (status == 'in_progress') {
          // This case shouldn't happen if the list is correct and patientIndex is for a 'pending' appt
          // If it did, we'd need the start time of the current consultation
        }
      }
      // Consider the time spent on the current 'in_progress' if any
      if (completedOrInProgressCount > 0 &&
          allAppointments[completedOrInProgressCount - 1]['status'] ==
              'in_progress') {
        // This is complex without tracking current consultation start time in ViewModel
        // For simplicity now, we'll use the total active session duration if it exceeds estimated based on average
        estimatedTimeSpent = activeSessionDuration;
      } else {
        estimatedTimeSpent = timeSpentOnPrevious;
      }
    }
    // Ensure estimatedTimeSpent does not exceed activeSessionDuration significantly if the current appointment is quick
    if (estimatedTimeSpent >
            activeSessionDuration +
                Duration(minutes: averageConsultationTime) &&
        patientIndex > 0) {
      // This is a heuristic - if estimated time based on average is much more than actual time plus one average slot,
      // it implies earlier appointments were faster. Adjust estimated time spent to actual time.
      estimatedTimeSpent = activeSessionDuration;
    }

    // Estimate time remaining for appointments before the patient (excluding the patient's own)
    Duration timeRemainingBeforePatient = estimatedTimeSpent;
    for (int i = 0; i < patientIndex; i++) {
      // For calculating time remaining, we need to know how many slots *before* this patient
      // are yet to start. The 'completedOrInProgressCount' is for those already past.
      // Let's rethink the calculation based on pending patients before the current one.
    }

    // Correct approach: Calculate time for pending patients before the current one.
    int pendingPatientsBefore = 0;
    for (int i = 0; i < patientIndex; i++) {
      if (allAppointments[i]['status'] == 'pending') {
        pendingPatientsBefore++;
      }
    }

    // Find the index of the current 'in_progress' patient, if any
    int currentConsultationIndex =
        allAppointments.indexWhere((appt) => appt['status'] == 'in_progress');

    Duration estimatedTimeFromNow = Duration.zero;

    if (currentConsultationIndex != -1 &&
        currentConsultationIndex < patientIndex) {
      // If there's a patient currently in consultation before our target patient,
      // we need to estimate how much longer that consultation will take.
      // Without the start time of the current consultation, we'll have to assume average time remains
      // This is a simplification.
      estimatedTimeFromNow += Duration(
          minutes:
              averageConsultationTime); // Assume one average consultation remains for the current patient
      pendingPatientsBefore--; // Exclude the current in-progress patient from pending count
    } else if (currentConsultationIndex == -1 &&
        completedOrInProgressCount > 0) {
      // No one in progress, but some completed
      // This case implies doctor is idle between patients, or next patient is just starting
      // We can assume the next patient (if any) will take average time
      // The logic below accounts for pending patients
    }

    // Add time for pending patients before the target patient
    estimatedTimeFromNow +=
        Duration(minutes: pendingPatientsBefore * averageConsultationTime);

    if (estimatedTimeFromNow.inMinutes < 1 && patientStatus == 'pending') {
      // If estimated time is very small and patient is still pending, they are likely next.
      return "You are next.";
    } else if (estimatedTimeFromNow.inMinutes < 1) {
      return "Calculating..."; // Should not happen for pending patient far down the list
    }

    // Add a buffer based on variability (using average consultation time as a simple proxy for variability)
    // A more advanced approach would use standard deviation as you mentioned.
    // For simplicity now, add a fixed percentage or a fraction of average time as buffer per patient.
    // Let's add 1 minute buffer per pending patient before.
    Duration bufferTime = Duration(minutes: pendingPatientsBefore);

    estimatedTimeFromNow += bufferTime;

    final totalMinutes = estimatedTimeFromNow.inMinutes;

    if (totalMinutes < 60) {
      return "Approx. $totalMinutes minutes waiting time.";
    } else {
      final hours = totalMinutes ~/ 60;
      final remainingMinutes = totalMinutes % 60;
      return "Approx. $hours hour(s) and $remainingMinutes minutes waiting time.";
    }
  }
}
