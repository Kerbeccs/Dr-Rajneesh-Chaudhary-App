import 'package:get_it/get_it.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import '../services/database_service.dart';
import '../services/compounder_payment_service.dart';

/// Global service locator instance
/// This provides a single source of truth for all services across the app
final GetIt locator = GetIt.instance;

/// Setup dependency injection
/// Call this once at app startup (in main.dart)
void setupLocator() {
  // Register Firebase instances as singletons
  // These are shared across the entire app
  locator.registerLazySingleton<FirebaseFirestore>(
    () => FirebaseFirestore.instance,
  );
  
  locator.registerLazySingleton<FirebaseAuth>(
    () => FirebaseAuth.instance,
  );
  
  locator.registerLazySingleton<FirebaseStorage>(
    () => FirebaseStorage.instance,
  );
  
  // Register ImagePicker as singleton
  // Reusing the same instance across the app
  locator.registerLazySingleton<ImagePicker>(
    () => ImagePicker(),
  );
  
  // Register DatabaseService as singleton
  // All ViewModels will share the same instance = consistent cache
  locator.registerLazySingleton<DatabaseService>(
    () => DatabaseService(),
  );
  
  // Register CompounderPaymentService as singleton
  // Shared payment service instance
  locator.registerLazySingleton<CompounderPaymentService>(
    () => CompounderPaymentService(),
  );
}
