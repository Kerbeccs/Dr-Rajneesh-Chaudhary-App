# 🔧 Fix: INVALID_CERT_HASH Error

## ❌ **Error from Logcat**

```
E/FirebaseAuth: [GetAuthDomainTask] Error getting project config. Failed with INVALID_CERT_HASH 400
E/zzb: Failed to get reCAPTCHA token with error [There was an error while trying to get your package certificate hash.]
W/LocalRequestInterceptor: Error getting App Check token; using placeholder token instead. Error: Too many attempts.
```

---

## 🎯 **Root Cause**

Your `google-services.json` file only has **ONE certificate hash** (SHA-1), but Firebase needs **ALL certificates** to be properly configured:

1. ✅ SHA-1 (local keystore) - `e0d1178c509baf609128f3d146c601b59a9b6899` (already in file)
2. ❌ SHA-256 (local keystore) - Missing from `google-services.json`
3. ❌ SHA-1 (Play App Signing) - Missing from `google-services.json`
4. ❌ SHA-256 (Play App Signing) - Missing from `google-services.json`

**The `google-services.json` file needs to be re-downloaded after adding ALL certificates to Firebase Console.**

---

## ✅ **SOLUTION: Re-download google-services.json**

### **Step 1: Verify All Certificates Are in Firebase Console**

1. **Go to Firebase Console:**
   - https://console.firebase.google.com
   - Select project: `doctorappointmentapp-d2f4f`

2. **Check Project Settings:**
   - Click gear icon (⚙️) → **"Project settings"**
   - Scroll to **"Your apps"**
   - Click on **"Dr. Rajnish Appointment"** (`com.drrajnish.appointment`)

3. **Verify SHA Certificates:**
   You should see **ALL 4 certificates** listed:
   - ✅ SHA-1 (local): `E0:D1:17:8C:50:9B:AF:60:91:28:F3:D1:46:C6:01:B5:9A:9B:68:99`
   - ✅ SHA-256 (local): `80:AD:D7:42:FD:F7:31:96:8B:64:B9:2D:EB:81:28:90:A4:80:78:46:5D:CA:BB:0D:C6:AC:C2:13:29:C1:EB:92`
   - ✅ SHA-1 (Play): `F5:21:B3:89:F0:F8:E5:02:E7:14:F2:22:84:30:5F:49:B5:2B:72:D0`
   - ✅ SHA-256 (Play): `A1:65:E6:D0:31:87:E6:85:34:2E:CD:03:AF:1A:42:FE:B4:1C:DB:6C:58:8F:23:40:42:1E:D9:16:63:80:3B:27`

4. **If any are missing, add them:**
   - Click **"Add fingerprint"**
   - Paste the certificate
   - Click **"Save"**

---

### **Step 2: Re-download google-services.json**

**This is CRITICAL!** After adding certificates, you MUST re-download the file:

1. **In Firebase Console:**
   - Still in Project Settings → Your apps
   - Click on **"Dr. Rajnish Appointment"** app
   - Click **"Download google-services.json"** button

2. **Replace the file:**
   - Save the downloaded file
   - Replace `android/app/google-services.json` with the new file

3. **Verify the new file:**
   - The new `google-services.json` should have updated OAuth client configuration
   - It may have multiple `oauth_client` entries for different certificates

---

### **Step 3: Wait for Firebase Propagation**

After re-downloading `google-services.json`:
- **Wait 5-10 minutes** for Firebase to propagate the changes
- Firebase needs time to update its backend configuration

---

### **Step 4: Rebuild the App**

```bash
# Clean build
flutter clean

# Rebuild release APK
flutter build apk --release

# Or rebuild AAB for Play Store
flutter build appbundle --release
```

---

## 🔍 **Why This Happens**

When you add SHA certificates to Firebase Console:
1. Firebase creates OAuth client configurations for each certificate
2. These configurations are stored in `google-services.json`
3. **If you don't re-download the file**, your app still has the old configuration
4. Firebase can't match your app's certificate → `INVALID_CERT_HASH` error

---

## ⚠️ **Important Notes**

1. **Always re-download `google-services.json`** after adding/removing SHA certificates
2. **Wait 5-10 minutes** after adding certificates before testing
3. **For local release builds**, Firebase uses your local keystore SHA certificates
4. **For Play Store builds**, Firebase uses Play App Signing SHA certificates

---

## 🚀 **After Fixing**

Once you've:
1. ✅ Added all 4 SHA certificates to Firebase Console
2. ✅ Re-downloaded `google-services.json`
3. ✅ Replaced the file in your project
4. ✅ Waited 5-10 minutes
5. ✅ Rebuilt the app

The `INVALID_CERT_HASH` error should be gone, and OTP should work correctly!

---

## 📝 **Quick Checklist**

- [ ] All 4 SHA certificates added to Firebase Console
- [ ] `google-services.json` re-downloaded from Firebase Console
- [ ] Old `google-services.json` replaced with new one
- [ ] Waited 5-10 minutes for Firebase propagation
- [ ] App rebuilt (`flutter clean && flutter build apk --release`)
- [ ] Tested OTP - should work now!

