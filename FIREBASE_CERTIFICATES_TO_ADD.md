# 🔑 Firebase Certificates to Add

## ✅ **Your Local Keystore Certificates**

These are for debug/local builds:

### **SHA-1:**
```
E0:D1:17:8C:50:9B:AF:60:91:28:F3:D1:46:C6:01:B5:9A:9B:68:99
```

### **SHA-256:**
```
80:AD:D7:42:FD:F7:31:96:8B:64:B9:2D:EB:81:28:90:A4:80:78:46:5D:CA:BB:0D:C6:AC:C2:13:29:C1:EB:92
```

---

## 🎯 **CRITICAL: Google Play App Signing SHA-256**

**This is the MOST IMPORTANT one!** You need to get this from Play Console:

### **How to Get It:**

1. **Go to Google Play Console:**
   - https://play.google.com/console
   - Select your app: **Dr. Rajnish**

2. **Navigate to App Signing:**
   - Left sidebar → **"Release"** → **"Setup"** → **"App signing"**
   - OR: **"Release"** → **"Production"** → **"App signing"**

3. **Find SHA-256 Certificate:**
   - Look for section: **"App signing key certificate"**
   - Copy the **SHA-256 certificate fingerprint** (long hex string)

4. **If you don't see it:**
   - You might need to upload a release first
   - Or check: **"Release"** → **"Setup"** → **"App integrity"**

---

## 📋 **Steps to Add to Firebase:**

1. **Go to Firebase Console:**
   - https://console.firebase.google.com
   - Select your project

2. **Project Settings:**
   - Click gear icon (⚙️) → **"Project settings"**
   - Scroll to **"Your apps"** section

3. **Find Your Android App:**
   - Look for app with package: `com.drrajnish.appointment`
   - Click settings icon (⚙️) next to it

4. **Add SHA-1:**
   - Scroll to **"SHA certificate fingerprints"**
   - Click **"Add fingerprint"**
   - Paste: `E0:D1:17:8C:50:9B:AF:60:91:28:F3:D1:46:C6:01:B5:9A:9B:68:99`
   - Click **"Save"**

5. **Add Local SHA-256:**
   - Click **"Add fingerprint"** again
   - Paste: `80:AD:D7:42:FD:F7:31:96:8B:64:B9:2D:EB:81:28:90:A4:80:78:46:5D:CA:BB:0D:C6:AC:C2:13:29:C1:EB:92`
   - Click **"Save"**

6. **Add Play App Signing SHA-256 (CRITICAL!):**
   - Click **"Add fingerprint"** again
   - Paste the **Play App Signing SHA-256** (from Play Console)
   - Click **"Save"**

7. **Download Updated google-services.json:**
   - Click **"Download google-services.json"**
   - Replace `android/app/google-services.json` with the new file

---

## ⚠️ **Important Notes:**

- ✅ Add **ALL 3 certificates** (SHA-1, local SHA-256, Play SHA-256)
- ✅ The **Play App Signing SHA-256** is what's missing - that's why you're getting the error!
- ✅ Wait 5-10 minutes after adding for Firebase to update
- ✅ Make sure package name in Firebase is `com.drrajnish.appointment` (not `com.example.test_app`)

---

## 🚀 **After Adding:**

1. Rebuild the app:
   ```bash
   flutter clean
   flutter build appbundle --release
   ```

2. Upload new AAB to Play Console

3. Test the app - Firebase Authentication should work!

---

## 📝 **Quick Copy-Paste:**

**SHA-1:**
```
E0:D1:17:8C:50:9B:AF:60:91:28:F3:D1:46:C6:01:B5:9A:9B:68:99
```

**SHA-256 (Local):**
```
80:AD:D7:42:FD:F7:31:96:8B:64:B9:2D:EB:81:28:90:A4:80:78:46:5D:CA:BB:0D:C6:AC:C2:13:29:C1:EB:92
```

**SHA-256 (Play App Signing):** ← **GET THIS FROM PLAY CONSOLE!**

