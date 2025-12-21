# 🔧 Fix: OTP "SMS Expired" Error After Package Name Change

## ❌ **Problem**
- OTP was working before
- After changing package name to `com.drrajnish.appointment`, getting "SMS expired" error
- OTP is received but verification fails

## 🎯 **Root Cause**
When you changed the package name, Firebase needs to be configured for the **new package name**. The issue is likely:

1. **Firebase Phone Authentication not enabled** for new package name
2. **SHA certificates not added** to Firebase for new package name
3. **Firebase Console app configuration** mismatch

---

## ✅ **SOLUTION: Check These in Firebase Console**

### **Step 1: Verify Firebase Phone Authentication is Enabled**

1. **Go to Firebase Console:**
   - https://console.firebase.google.com
   - Select project: **doctorappointmentapp-d2f4f**

2. **Navigate to Authentication:**
   - Left sidebar → **"Authentication"** → **"Sign-in method"**

3. **Check Phone Authentication:**
   - Look for **"Phone"** in the sign-in providers list
   - Should show: **"Enabled"** ✅
   - If disabled, click **"Phone"** → **"Enable"** → **"Save"**

4. **Check App Verification:**
   - In Phone settings, check **"App verification"**
   - Make sure it's set up correctly

---

### **Step 2: Verify Android App Configuration**

1. **Go to Project Settings:**
   - Gear icon (⚙️) → **"Project settings"**
   - Scroll to **"Your apps"** section

2. **Check if BOTH apps exist:**
   - ✅ `com.drrajnish.appointment` (new - should be active)
   - ⚠️ `com.example.test_app` (old - can be removed or kept)

3. **For `com.drrajnish.appointment` app:**
   - Click settings icon (⚙️) next to it
   - Verify:
     - Package name: `com.drrajnish.appointment`
     - SHA-1 certificate: Added ✅
     - SHA-256 certificate: Added ✅ (both local and Play App Signing)

---

### **Step 3: Check Firebase Quota/Limits**

1. **Go to Firebase Console:**
   - **"Authentication"** → **"Usage"** tab
   - Check if you've hit any quotas

2. **Check Phone Auth Quota:**
   - Free tier: 10,000 verifications/month
   - If exceeded, you'll need to upgrade

---

### **Step 4: Verify google-services.json**

Your `google-services.json` has TWO clients. Make sure the app is using the correct one:

**Current `google-services.json` has:**
- Client 1: `com.drrajnish.appointment` ✅ (should be used)
- Client 2: `com.example.test_app` (old, can cause conflicts)

**The app should automatically use the one matching `applicationId` in `build.gradle`.**

---

### **Step 5: Re-download google-services.json**

1. **Firebase Console:**
   - Project Settings → Your apps
   - Click on `com.drrajnish.appointment` app
   - Click **"Download google-services.json"**

2. **Replace the file:**
   - Replace `android/app/google-services.json` with the new one
   - Make sure it has the correct package name

3. **Rebuild:**
   ```bash
   flutter clean
   flutter pub get
   flutter build apk --debug  # Test with debug first
   ```

---

## 🔍 **Most Likely Issues**

### **Issue 1: SHA Certificates Not Added**
**Symptom:** "SMS expired" or "App not authorized"

**Fix:**
- Go to Firebase Console → Project Settings → Your apps
- Click `com.drrajnish.appointment` app
- Add SHA-1 and SHA-256 certificates
- Wait 5-10 minutes for propagation

### **Issue 2: Phone Auth Not Enabled for New Package**
**Symptom:** OTP never arrives or verification fails immediately

**Fix:**
- Firebase Console → Authentication → Sign-in method
- Enable Phone authentication
- Verify app is registered

### **Issue 3: Wrong Firebase App Being Used**
**Symptom:** Works sometimes, fails other times

**Fix:**
- Check `google-services.json` has correct `mobilesdk_app_id`
- Should match the app in Firebase Console
- Re-download `google-services.json` if needed

---

## 🚀 **Quick Fix Steps**

1. ✅ **Firebase Console** → **Authentication** → **Sign-in method** → Enable **Phone**
2. ✅ **Firebase Console** → **Project Settings** → Verify `com.drrajnish.appointment` app exists
3. ✅ **Firebase Console** → **Project Settings** → Add SHA certificates for new package
4. ✅ **Re-download** `google-services.json` from Firebase Console
5. ✅ **Replace** `android/app/google-services.json`
6. ✅ **Rebuild** app: `flutter clean && flutter build apk --debug`
7. ✅ **Test** OTP again

---

## ⚠️ **Important Notes**

- **Wait 5-10 minutes** after adding SHA certificates for Firebase to update
- **Clear app data** before testing: Settings → Apps → Your App → Clear Data
- **Test with debug build first** before release build
- **Check Firebase Console logs** for authentication errors

---

## 📞 **If Still Not Working**

1. **Check Firebase Console → Authentication → Users:**
   - See if verification attempts are being logged
   - Check for error messages

2. **Check Firebase Console → Crashlytics:**
   - Look for authentication-related crashes

3. **Check Network:**
   - Make sure device has internet connection
   - Try on different network (WiFi vs Mobile data)

4. **Check Phone Number Format:**
   - Should be in E.164 format: `+911234567890`
   - No spaces or special characters

---

## 🎯 **Summary**

The "SMS expired" error after package name change is almost always because:
1. SHA certificates not added to Firebase for new package name
2. Phone authentication not properly configured for new package
3. Wrong `google-services.json` being used

**Fix:** Add SHA certificates, enable Phone auth, re-download `google-services.json`, rebuild.

