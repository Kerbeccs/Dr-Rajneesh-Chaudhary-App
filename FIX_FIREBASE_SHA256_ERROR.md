# 🔧 Fix: Firebase Authentication SHA-256 Error

## ❌ **Error Message**
```
This app is not authorized to use Firebase Authentication. 
Please verify that the correct package name, SHA-1, and SHA-256 are configured in the Firebase Console. 
[A play_integrity token was passed, but no matching SHA-256 was registered in the Firebase console.]
```

## 🎯 **Root Cause**
When you changed package name from `com.example.test_app` to `com.drrajnish.appointment`, Firebase needs:
1. ✅ **Your local keystore SHA-1 and SHA-256** (for debug builds)
2. ✅ **Google Play App Signing certificate SHA-256** (for Play Store builds) ← **THIS IS MISSING!**

**The old SHA-1/SHA-256 from `com.example.test_app` won't work for the new package name!**

---

## ✅ **SOLUTION: Add Both Certificates to Firebase**

### **Step 1: Get Your Local Keystore SHA-1 and SHA-256**

#### **Option A: Using keytool (Recommended)**

```bash
# Get SHA-1
keytool -list -v -keystore keystores/doctor-app-keystore.jks -alias doctor-app-key

# Get SHA-256 (same command, look for SHA256 line)
keytool -list -v -keystore keystores/doctor-app-keystore.jks -alias doctor-app-key
```

**You'll see output like:**
```
Certificate fingerprints:
     SHA1: A1:B2:C3:D4:E5:F6:... (copy this)
     SHA256: 12:34:56:78:90:AB:CD:EF:... (copy this)
```

**If you don't know the keystore password or alias:**
- Check `android/keystore.properties` file (if it exists)
- Or check your notes/documentation

#### **Option B: Using Gradle (Easier)**

```bash
# Navigate to android folder
cd android

# Run this command (it will prompt for keystore password)
./gradlew signingReport
```

**On Windows:**
```cmd
cd android
gradlew.bat signingReport
```

**Look for output like:**
```
Variant: release
Config: release
Store: C:\Users\Dell\...\keystores\doctor-app-keystore.jks
Alias: doctor-app-key
SHA1: A1:B2:C3:D4:E5:F6:...
SHA256: 12:34:56:78:90:AB:CD:EF:...
```

---

### **Step 2: Get Google Play App Signing Certificate SHA-256**

**This is the MOST IMPORTANT one for Play Store builds!**

1. **Go to Google Play Console:**
   - https://play.google.com/console
   - Select your app: **Dr. Rajnish** (or your app name)

2. **Navigate to App Signing:**
   - Left sidebar → **"Release"** → **"Setup"** → **"App signing"**
   - OR: **"Release"** → **"Production"** → **"App signing"**

3. **Find the SHA-256 Certificate:**
   - Look for section: **"App signing key certificate"**
   - You'll see:
     ```
     SHA-256 certificate fingerprint:
     12:34:56:78:90:AB:CD:EF:12:34:56:78:90:AB:CD:EF:12:34:56:78:90:AB:CD:EF:12:34:56:78:90:AB:CD:EF
     ```
   - **Copy this SHA-256 fingerprint** (the long hex string)

4. **If you don't see App Signing section:**
   - You might need to upload at least one release first
   - Or check **"Release"** → **"Setup"** → **"App integrity"**

---

### **Step 3: Add Certificates to Firebase Console**

1. **Go to Firebase Console:**
   - https://console.firebase.google.com
   - Select your project

2. **Navigate to Project Settings:**
   - Click gear icon (⚙️) → **"Project settings"**

3. **Go to "Your apps" section:**
   - Scroll down to **"Your apps"**
   - Find your Android app with package name: `com.drrajnish.appointment`
   - Click the **settings icon (⚙️)** next to it

4. **Add SHA-1 Certificate:**
   - Scroll to **"SHA certificate fingerprints"**
   - Click **"Add fingerprint"**
   - Paste your **local keystore SHA-1** (from Step 1)
   - Click **"Save"**

5. **Add SHA-256 Certificates (IMPORTANT - Add BOTH!):**
   - Click **"Add fingerprint"** again
   - Paste your **local keystore SHA-256** (from Step 1)
   - Click **"Save"**
   
   - Click **"Add fingerprint"** again
   - Paste your **Google Play App Signing SHA-256** (from Step 2) ← **THIS IS CRITICAL!**
   - Click **"Save"**

6. **Verify Package Name:**
   - Make sure package name shows: `com.drrajnish.appointment`
   - If it still shows `com.example.test_app`, you need to:
     - Either update the existing app's package name (if possible)
     - Or add a NEW Android app with the correct package name

---

### **Step 4: Download Updated google-services.json**

1. **In Firebase Console:**
   - After adding certificates, click **"Download google-services.json"**
   - OR: Go to **"Project settings"** → **"Your apps"** → Click **"google-services.json"**

2. **Replace the file:**
   - Copy the downloaded `google-services.json`
   - Replace: `android/app/google-services.json`
   - Make sure it has package name: `com.drrajnish.appointment`

3. **Verify the file:**
   - Open `android/app/google-services.json`
   - Search for `"package_name"`
   - Should show: `"com.drrajnish.appointment"` (not `com.example.test_app`)

---

### **Step 5: Rebuild and Test**

```bash
# Clean build
flutter clean

# Get dependencies
flutter pub get

# Build release AAB
flutter build appbundle --release
```

**Then:**
1. Upload new AAB to Play Console
2. Test the app from Play Store
3. Firebase Authentication should work now!

---

## 🔍 **Quick Checklist**

- [ ] Got local keystore SHA-1 (from `keytool` or `gradlew signingReport`)
- [ ] Got local keystore SHA-256 (from `keytool` or `gradlew signingReport`)
- [ ] Got Google Play App Signing SHA-256 (from Play Console → App signing)
- [ ] Added all 3 certificates to Firebase Console
- [ ] Verified package name in Firebase is `com.drrajnish.appointment`
- [ ] Downloaded and replaced `google-services.json`
- [ ] Rebuilt the app

---

## ⚠️ **Common Issues**

### **Issue 1: Can't find App Signing in Play Console**
- **Solution:** You need to upload at least one release first
- After uploading AAB, Google will generate the App Signing certificate
- Then you can see it in **"Release"** → **"Setup"** → **"App signing"**

### **Issue 2: Firebase still shows old package name**
- **Solution:** 
  - Option A: Update the existing app's package name in Firebase (if allowed)
  - Option B: Add a NEW Android app in Firebase with package name `com.drrajnish.appointment`
  - Then download the new `google-services.json`

### **Issue 3: Don't know keystore password**
- **Solution:** 
  - Check `android/keystore.properties` file
  - Check your notes/documentation
  - If lost, you'll need to create a new keystore (but this breaks Play Store updates!)

### **Issue 4: Error persists after adding certificates**
- **Solution:**
  - Wait 5-10 minutes for Firebase to propagate changes
  - Clear app data and reinstall
  - Make sure you added the **Play App Signing SHA-256** (not just local keystore)

---

## 🎯 **Most Important Step**

**The Play App Signing SHA-256 is CRITICAL!**

When users download from Play Store, Google signs the app with their certificate, not yours. That's why you need the Play App Signing SHA-256 in Firebase.

**To get it:**
1. Play Console → **Release** → **Setup** → **App signing**
2. Copy the **SHA-256 certificate fingerprint**
3. Add it to Firebase Console

---

## 📝 **Summary**

1. ✅ Get local keystore SHA-1 and SHA-256
2. ✅ Get Google Play App Signing SHA-256 (from Play Console)
3. ✅ Add all 3 to Firebase Console
4. ✅ Download updated `google-services.json`
5. ✅ Rebuild and test

**The Play App Signing SHA-256 is what's missing!** That's why the error says "play_integrity token" - it's Google Play's certificate.

---

## 🚀 **After Fixing**

Once you add the Play App Signing SHA-256 to Firebase:
- ✅ Play Store builds will work
- ✅ Firebase Authentication will work
- ✅ No more "app not authorized" error

**Test it:** Install the app from Play Store internal testing link and try logging in!

