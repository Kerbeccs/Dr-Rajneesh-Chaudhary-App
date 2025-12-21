# 🔑 Firebase Certificates - Correct Format

## ✅ **SHA-1 Certificate (Local Keystore)**

### **With Colons (Standard Format):**
```
E0:D1:17:8C:50:9B:AF:60:91:28:F3:D1:46:C6:01:B5:9A:9B:68:99
```

### **Without Colons (If Firebase Rejects With Colons):**
```
E0D1178C509BAF609128F3D146C601B59A9B6899
```

---

## ✅ **SHA-256 Certificate (Local Keystore)**

### **With Colons (Standard Format):**
```
80:AD:D7:42:FD:F7:31:96:8B:64:B9:2D:EB:81:28:90:A4:80:78:46:5D:CA:BB:0D:C6:AC:C2:13:29:C1:EB:92
```

### **Without Colons (If Firebase Rejects With Colons):**
```
80ADD742FDF731968B64B92DEB812890A48078465DCABB0DC6ACC21329C1EB92
```

---

## 🎯 **How to Add in Firebase Console**

### **Option 1: Try With Colons First**
1. Copy the fingerprint **with colons** (standard format)
2. Paste into Firebase Console
3. If it works, you're done!

### **Option 2: If Firebase Rejects, Use Without Colons**
1. Copy the fingerprint **without colons** (remove all `:` characters)
2. Paste into Firebase Console
3. Should work now!

---

## 📋 **Quick Copy-Paste (Without Colons)**

**SHA-1:**
```
E0D1178C509BAF609128F3D146C601B59A9B6899
```

**SHA-256 (Local):**
```
80ADD742FDF731968B64B92DEB812890A48078465DCABB0DC6ACC21329C1EB92
```

---

## ⚠️ **Important Notes**

- Firebase Console sometimes accepts **with colons**, sometimes **without**
- If you get "does not match format" error, try **without colons**
- Make sure there are **no spaces** in the fingerprint
- All characters should be **uppercase** (A-F, 0-9)

---

## 🔍 **Verify Format**

The fingerprint should be:
- **SHA-1:** 40 characters (20 bytes × 2) = `E0D1178C509BAF609128F3D146C601B59A9B6899`
- **SHA-256:** 64 characters (32 bytes × 2) = `80ADD742FDF731968B64B92DEB812890A48078465DCABB0DC6ACC21329C1EB92`

---

## 🚀 **Steps to Add**

1. **Go to Firebase Console:**
   - https://console.firebase.google.com
   - Project Settings → Your apps → Android app

2. **Add SHA-1:**
   - Try: `E0:D1:17:8C:50:9B:AF:60:91:28:F3:D1:46:C6:01:B5:9A:9B:68:99`
   - If rejected, try: `E0D1178C509BAF609128F3D146C601B59A9B6899`

3. **Add SHA-256:**
   - Try: `80:AD:D7:42:FD:F7:31:96:8B:64:B9:2D:EB:81:28:90:A4:80:78:46:5D:CA:BB:0D:C6:AC:C2:13:29:C1:EB:92`
   - If rejected, try: `80ADD742FDF731968B64B92DEB812890A48078465DCABB0DC6ACC21329C1EB92`

4. **Add Play App Signing SHA-256:**
   - Get from Play Console → Release → Setup → App signing
   - Add in same format (with or without colons, whichever works)

---

## ✅ **After Adding**

1. Wait 5-10 minutes for Firebase to update
2. Download updated `google-services.json`
3. Replace `android/app/google-services.json`
4. Rebuild and test!

