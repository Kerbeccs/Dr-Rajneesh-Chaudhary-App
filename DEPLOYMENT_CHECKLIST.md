# 🚀 Play Store Deployment Checklist

## ✅ Pre-Deployment Security Fixes (MUST DO FIRST)

- [ ] **Fix Firestore Security Rules** - Replace permissive rules with role-based access
- [ ] **Remove Keystore Passwords** - Move to keystore.properties (gitignored)
- [ ] **Remove Test Credentials** - Delete hardcoded doctor/compounder logins
- [ ] **Remove Plaintext Passwords** - Use Firebase Auth or hash passwords
- [ ] **Enable Firebase App Check** - Protect API keys
- [ ] **Replace Razorpay Test Key** - Use production key from environment

## ✅ Logging Implementation

- [ ] **Add Logging Dependencies** - logger, firebase_crashlytics, firebase_analytics
- [ ] **Create LoggingService** - Centralized logging with levels
- [ ] **Replace All print()** - Use LoggingService methods
- [ ] **Enable Crashlytics** - In main.dart
- [ ] **Enable Analytics** - Track user actions

## ✅ Performance Fixes

- [ ] **Add Pagination** - getAllPatientsForDoctorDashboard()
- [ ] **Add Pagination** - getPatientReports()
- [ ] **Add Pagination** - fetchBookings()
- [ ] **Deploy Firestore Indexes** - Run `firebase deploy --only firestore:indexes`
- [ ] **Fix Concurrency Issues** - Add locks to critical sections
- [ ] **Enable Offline Persistence** - Firestore settings

## ✅ App Configuration

- [ ] **Update applicationId** - Change from `com.example.test_app`
- [ ] **Update App Name** - In AndroidManifest.xml
- [ ] **Add App Icon** - Replace default Flutter icon
- [ ] **Update Version** - Increment versionCode and versionName
- [ ] **Enable ProGuard** - Set minifyEnabled = true for release

## ✅ Testing

- [ ] **Test on Multiple Android Versions** - API 23-34
- [ ] **Test on Different Screen Sizes** - Phone, tablet
- [ ] **Test Offline Functionality** - App should work offline
- [ ] **Test Payment Flow** - End-to-end Razorpay integration
- [ ] **Test Login Flows** - All authentication methods
- [ ] **Test Appointment Booking** - Complete booking flow
- [ ] **Test Release Build** - Build and test AAB file

## ✅ Play Store Preparation

- [ ] **Create Privacy Policy** - Host on website/GitHub Pages
- [ ] **Create Play Console Account** - Pay $25 one-time fee
- [ ] **Prepare Store Listing**:
  - [ ] App name and description
  - [ ] Screenshots (phone and tablet)
  - [ ] Feature graphic
  - [ ] Privacy policy URL
- [ ] **Complete Content Rating** - Fill out questionnaire
- [ ] **Set Pricing** - Free or paid
- [ ] **Build Release AAB** - `flutter build appbundle --release`

## ✅ Post-Deployment

- [ ] **Monitor Crashlytics** - Check for crashes
- [ ] **Monitor Analytics** - Track user behavior
- [ ] **Set Up Alerts** - Firebase Console alerts
- [ ] **Plan Gradual Rollout** - 5% → 50% → 100%
- [ ] **Backup Keystore** - Store securely (if lost, cannot update app)

---

## 🔴 CRITICAL - Do Not Deploy Until Fixed

1. Firestore security rules allow anyone to read/write all data
2. Keystore passwords exposed in code
3. Test credentials work in production
4. Passwords stored in plaintext
5. API keys not protected

---

**Status:** ⚠️ NOT READY FOR DEPLOYMENT  
**Blockers:** 5 critical security issues  
**Estimated Fix Time:** 1-2 weeks


