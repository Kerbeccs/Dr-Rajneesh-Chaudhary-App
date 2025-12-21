# How to Set Up Doctor and Compounder Credentials

## Current Situation

After removing hardcoded credentials, you need to create the `admin_credentials` collection in Firestore. This collection stores login credentials for doctor and compounder.

## Step-by-Step Setup

### Method 1: Using Firebase Console (Manual - You need to hash password yourself)

**Note:** In this method, you manually create the collection and documents in Firebase Console. You MUST generate the password hash yourself (use Method 2 below to generate it) and paste the hash into the `passwordHash` field.

1. **Go to Firebase Console**
   - Visit: https://console.firebase.google.com
   - Select your project
   - Go to **Firestore Database**

2. **Create `admin_credentials` Collection**
   - Click **Start collection** (if Firestore is empty) or **Add collection**
   - Collection ID: `admin_credentials`
   - Click **Next**

3. **Add Doctor Document**
   - Document ID: Click **Auto-ID** (let Firebase generate it)
   - Add these fields:
     ```
     Field name: phoneNumber
     Type: string
     Value: +919415148932
     
     Field name: passwordHash
     Type: string
     Value: [Use Method 2 below to generate hash for password 'drjc01']
     
     Field name: role
     Type: string
     Value: doctor
     
     Field name: name
     Type: string
     Value: Dr. Rajnish
     
     Field name: email
     Type: string
     Value: drjc@example.com
     
     Field name: age
     Type: number
     Value: 40
     ```

4. **Add Compounder Document**
   - Click **Add document** in `admin_credentials` collection
   - Document ID: Auto-ID
   - Add these fields:
     ```
     Field name: phoneNumber
     Type: string
     Value: +911234567890
     
     Field name: passwordHash
     Type: string
     Value: [Use Method 2 below to generate hash for password 'assist00']
     
     Field name: role
     Type: string
     Value: compounder
     
     Field name: name
     Type: string
     Value: Compounder
     
     Field name: email
     Type: string
     Value: compounder@example.com
     
     Field name: age
     Type: number
     Value: 0
     ```

### Method 2: Generate Password Hashes (Helper for Method 1)

**Purpose:** This method helps you generate the SHA-256 hash needed for Method 1. If you're using Method 1, you need this to create the password hash.

**For password `drjc01` (doctor):**
- SHA-256 Hash: `a8f5f167f44f4964e6c998dee827110c` (example - generate your own)

**For password `assist00` (compounder):**
- SHA-256 Hash: `[generate using tool below]`

**Generate Hash Online:**
1. Visit: https://emn178.github.io/online-tools/sha256.html
2. Enter password (e.g., `drjc01`)
3. Copy the hash
4. Paste in Firestore `passwordHash` field

**Or use command line:**
```bash
# If you have Node.js:
node -e "const crypto = require('crypto'); console.log(crypto.createHash('sha256').update('drjc01').digest('hex'));"

# Output: a8f5f167f44f4964e6c998dee827110c (example)
```

### Method 3: Using Flutter Code (Recommended)

Add this to your app temporarily and call it once:

```dart
import 'package:your_app/services/admin_auth_service.dart';

// Call this from a button or on app start (once)
Future<void> setupCredentials() async {
  // Doctor
  await AdminAuthService.createAdminCredentials(
    phoneNumber: '9415148932',
    password: 'drjc01',
    role: 'doctor',
    name: 'Dr. Rajnish',
    email: 'drjc@example.com',
    age: 40,
  );
  
  // Compounder
  await AdminAuthService.createAdminCredentials(
    phoneNumber: '1234567890',
    password: 'assist00',
    role: 'compounder',
    name: 'Compounder',
    email: 'compounder@example.com',
    age: 0,
  );
  
  print('Admin credentials created!');
}
```

## Verify Setup

After setup, test login:
1. Open your app
2. Enter phone: `9415148932`
3. Enter password: `drjc01`
4. Should login as doctor

## Where Data is Stored

### For Login (NEW):
- **Collection**: `admin_credentials`
- **Purpose**: Phone + hashed password for authentication
- **Location**: Firebase Console → Firestore → `admin_credentials`

### For User Profiles (EXISTING):
- **Collection**: `users`
- **Purpose**: User profile data (name, email, role, etc.)
- **Location**: Firebase Console → Firestore → `users`
- **Note**: May already have doctor/compounder records here

## Important Notes

1. **Phone Number Format**: Must be in E.164 format (e.g., `+919415148932`)
2. **Password Hash**: Never store plaintext passwords, always use hash
3. **Security**: The `admin_credentials` collection should have restricted access in Firestore rules
4. **Testing**: After setup, remove any temporary setup code

## Troubleshooting

- **Login fails**: Check phone number format (must include country code)
- **Password doesn't work**: Verify hash matches the password you're entering
- **Collection not found**: Make sure you created `admin_credentials` collection
- **Role not recognized**: Ensure role is exactly `doctor` or `compounder` (lowercase)

