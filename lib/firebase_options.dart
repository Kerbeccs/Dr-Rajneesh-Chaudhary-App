// File generated using the Firebase configs from your project
// This file contains Firebase configuration for multiple platforms

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
///
/// Example:
///
/// import 'firebase_options.dart';
/// // ...
/// await Firebase.initializeApp(
///   options: DefaultFirebaseOptions.currentPlatform,
/// );
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for ios - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for macos - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyC7MwxqqF1vaJsI6czwMd-pVP5BXpAtMFI',
    appId: '1:892539923138:web:1a19848f007f014dad295b',
    messagingSenderId: '892539923138',
    projectId: 'doctorappointmentapp-d2f4f',
    authDomain: 'doctorappointmentapp-d2f4f.firebaseapp.com',
    storageBucket: 'doctorappointmentapp-d2f4f.firebasestorage.app',
    measurementId: 'G-7REL32DT89',
    databaseURL:
        'https://doctorappointmentapp-d2f4f-default-rtdb.asia-southeast1.firebasedatabase.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBDVw_2bRI8IxDEDXmShXiUx0X8vA7kB3Q',
    appId: '1:892539923138:android:cef3a43f2f13f771ad295b',
    messagingSenderId: '892539923138',
    projectId: 'doctorappointmentapp-d2f4f',
    storageBucket: 'doctorappointmentapp-d2f4f.firebasestorage.app',
    databaseURL:
        'https://doctorappointmentapp-d2f4f-default-rtdb.asia-southeast1.firebasedatabase.app',
  );
}
