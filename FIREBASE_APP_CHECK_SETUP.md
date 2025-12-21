# 🔐 Firebase App Check Setup Guide

## ✅ **What Was Fixed**

1. **Added Firebase App Check initialization** in `main.dart`
   - Uses `AndroidProvider.playIntegrity` for production (Play Store builds)
   - Uses `AndroidProvider.debug` for local testing

2. **Fixed OTP redirect issue** in signup screen
   - Added same polling logic as login screen
   - Now waits for Firebase callbacks before showing OTP field

---

## 🎯 **Why This Fixes Your Issues**

### **Issue 1: OTP Not Redirecting (Local Release APK)**
- **Problem:** Signup screen checked `otpSent` immediately, but Firebase callback hadn't fired yet
- **Fix:** Added polling mechanism (waits up to 5 seconds) for Firebase to confirm OTP was sent
- **Result:** Now properly redirects to OTP input field

### **Issue 2: Play Store App Integrity/ReCAPTCHA Errors**
- **Problem:** Firebase App Check was not initialized, so Play Integrity API wasn't being used
- **Fix:** Added `FirebaseAppCheck.instance.activate()` with `AndroidProvider.playIntegrity` for production
- **Result:** Play Store builds will now pass integrity checks

---

## 📋 **Additional Setup Required**

### **Step 1: Get Debug Token (For Local Testing)**

When you run the app in debug mode, Firebase App Check will generate a debug token. You need to add this to Firebase Console:

1. **Run the app in debug mode:**
   ```bash
   flutter run
   ```

2. **Check logcat/console for debug token:**
   ```
   Firebase App Check debug token: [TOKEN_HERE]
   ```

3. **Add debug token to Firebase Console:**
   - Go to: https://console.firebase.google.com
   - Select project: `doctorappointmentapp-d2f4f`
   - Go to: **"Build"** → **"App Check"**
   - Click on your Android app: `com.drrajnish.appointment`
   - Under **"Debug tokens"**, click **"Add debug token"**
   - Paste the token from logcat
   - Click **"Save"**

**Note:** Debug tokens are only needed for local testing. Play Store builds use Play Integrity automatically.

---

### **Step 2: Enable App Check in Firebase Console**

1. **Go to Firebase Console:**
   - https://console.firebase.google.com
   - Select project: `doctorappointmentapp-d2f4f`

2. **Navigate to App Check:**
   - Left sidebar → **"Build"** → **"App Check"**

3. **Register your app:**
   - If not already registered, click **"Get started"**
   - Select your Android app: `com.drrajnish.appointment`
   - Choose **"Play Integrity"** as the provider
   - Click **"Register"**

4. **Enable enforcement (optional but recommended):**
   - After registration, you can enable enforcement for:
     - Cloud Firestore
     - Cloud Storage
     - Authentication
   - This ensures only legitimate app instances can access your Firebase services

---

## 🚀 **Testing**

### **Test Local Release APK:**
```bash
flutter clean
flutter build apk --release
# Install and test - OTP should now redirect properly
```

### **Test Play Store Build:**
```bash
flutter clean
flutter build appbundle --release
# Upload to Play Console - App Integrity errors should be gone
```

---

## ⚠️ **Important Notes**

1. **Debug Token Expires:**
   - Debug tokens may expire after some time
   - If local testing stops working, check logcat for a new token and add it to Firebase Console

2. **Play Integrity Requirements:**
   - Your app must be published on Play Store (at least in internal testing)
   - Play Integrity API must be enabled in Google Cloud Console
   - SHA-256 certificates must be added to Firebase (already done)

3. **Production vs Debug:**
   - **Debug builds:** Use debug token (needs manual setup)
   - **Release builds:** Use Play Integrity automatically (no setup needed if app is on Play Store)

---

## 🔍 **Troubleshooting**

### **Issue: "App Check token is invalid"**
- **Solution:** Make sure debug token is added to Firebase Console for local testing
- **For Play Store:** Ensure app is published and Play Integrity is enabled

### **Issue: "Play Integrity API not enabled"**
- **Solution:** 
  1. Go to Google Cloud Console
  2. Enable "Play Integrity API" for your project
  3. Wait 5-10 minutes for propagation

### **Issue: OTP still not redirecting**
- **Solution:** 
  1. Check if `authViewModel.otpSent` is being set to `true` in `auth_viewmodel.dart`
  2. Check Firebase Console → Authentication → Sign-in method → Phone (should be enabled)
  3. Verify SHA certificates are added correctly

---

## ✅ **Summary**

1. ✅ Firebase App Check is now initialized in `main.dart`
2. ✅ Signup screen OTP redirect is fixed
3. ⚠️ **You need to:** Add debug token to Firebase Console for local testing
4. ⚠️ **You need to:** Enable App Check in Firebase Console (if not already done)

After completing the additional setup steps, both issues should be resolved!

