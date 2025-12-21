import 'package:flutter/foundation.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:logger/logger.dart';

/// Centralized logging with levels, routes errors to Crashlytics in release.
class LoggingService {
  static final Logger _logger = Logger(
    printer: PrettyPrinter(
      methodCount: 2,
      errorMethodCount: 8,
      lineLength: 120,
      colors: true,
      printEmojis: true,
      noBoxingByDefault: false,
    ),
  );

  /// Info-level logs for normal app flow.
  static void info(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.i(message, error: error, stackTrace: stackTrace);
    if (kReleaseMode) {
      FirebaseCrashlytics.instance.log(message);
    }
  }

  /// Warning-level logs for recoverable issues.
  static void warning(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.w(message, error: error, stackTrace: stackTrace);
    if (kReleaseMode) {
      FirebaseCrashlytics.instance.log('WARNING: $message');
    }
  }

  /// Error-level logs and Crashlytics reporting in release builds.
  static void error(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.e(message, error: error, stackTrace: stackTrace);
    if (kReleaseMode) {
      FirebaseCrashlytics.instance.recordError(
        error ?? message,
        stackTrace ?? StackTrace.current,
        reason: message,
      );
    }
  }

  /// Debug logs shown only in debug/profile.
  static void debug(String message) {
    if (kDebugMode) {
      _logger.d(message);
    }
  }
}

