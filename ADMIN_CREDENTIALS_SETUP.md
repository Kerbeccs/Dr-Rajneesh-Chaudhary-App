# Admin Credentials Setup Guide

## Overview
Admin users (doctor and compounder) are now authenticated using Firestore collection `admin_credentials` with SHA-256 hashed passwords. This is more secure than hardcoded credentials.

## Firestore Collection Structure

### Collection: `admin_credentials`

Each document should have the following structure:

```json
{
  "phoneNumber": "+919415148932",
  "passwordHash": "a1b2c3d4e5f6...",  // SHA-256 hash of password
  "role": "doctor",  // or "compounder"
  "name": "Dr. Rajnish",
  "email": "drjc@example.com",
  "age": 40,
  "createdAt": "2024-01-01T00:00:00Z",
  "updatedAt": "2024-01-01T00:00:00Z"
}
```

## Setting Up Admin Credentials

### Option 1: Using Flutter Code (One-time setup)

Create a temporary Dart script or add this to your app temporarily:

```dart
import 'package:your_app/services/admin_auth_service.dart';

// Run this once to create admin credentials
Future<void> setupAdminCredentials() async {
  // Create doctor credentials
  await AdminAuthService.createAdminCredentials(
    phoneNumber: '9415148932',
    password: 'drjc01',  // This will be hashed automatically
    role: 'doctor',
    name: 'Dr. Rajnish',
    email: 'drjc@example.com',
    age: 40,
  );
  
  // Create compounder credentials
  await AdminAuthService.createAdminCredentials(
    phoneNumber: '1234567890',
    password: 'assist00',  // This will be hashed automatically
    role: 'compounder',
    name: 'Compounder',
    email: 'compounder@example.com',
    age: 0,
  );
}
```

### Option 2: Using Firebase Console (Manual)

1. Go to Firebase Console → Firestore Database
2. Create a new collection named `admin_credentials`
3. Add documents with the following fields:

**For Doctor:**
- `phoneNumber`: `+919415148932` (or your doctor's phone)
- `passwordHash`: Generate SHA-256 hash of password (see below)
- `role`: `doctor`
- `name`: `Dr. Rajnish`
- `email`: `drjc@example.com`
- `age`: `40`

**For Compounder:**
- `phoneNumber`: `+911234567890` (or your compounder's phone)
- `passwordHash`: Generate SHA-256 hash of password (see below)
- `role`: `compounder`
- `name`: `Compounder`
- `email`: `compounder@example.com`
- `age`: `0`

### Generating Password Hash

You can generate SHA-256 hash using:

**Online Tool:**
- Visit: https://emn178.github.io/online-tools/sha256.html
- Enter your password
- Copy the hash

**Using Flutter Code:**
```dart
import 'package:crypto/crypto.dart';
import 'dart:convert';

String hashPassword(String password) {
  final bytes = utf8.encode(password);
  final digest = sha256.convert(bytes);
  return digest.toString();
}

// Example:
print(hashPassword('drjc01'));  // Output: hash string
```

**Using Command Line (if you have Node.js):**
```bash
node -e "const crypto = require('crypto'); console.log(crypto.createHash('sha256').update('drjc01').digest('hex'));"
```

## Security Notes

1. **Password Hashing**: Passwords are hashed using SHA-256 before storage
2. **No Plaintext**: Never store passwords in plaintext
3. **Firestore Security Rules**: Ensure `admin_credentials` collection is protected:

```javascript
match /admin_credentials/{document} {
  // Only allow read/write from server-side or authenticated admin users
  allow read, write: if false;  // Disable client-side access
  // Or use Cloud Functions for admin management
}
```

4. **Phone Number Format**: Always use E.164 format (e.g., `+919415148932`)

## Testing

After setting up credentials, test login:
1. Use phone number: `9415148932` (or your doctor phone)
2. Use password: `drjc01` (or your doctor password)
3. Should authenticate and redirect to doctor dashboard

## Updating Credentials

To update admin credentials, you can:
1. Use Firebase Console to update the document
2. Use the `AdminAuthService.createAdminCredentials()` method (it updates if exists)

## Troubleshooting

- **Login fails**: Check that phone number matches exactly (including country code)
- **Password doesn't work**: Verify the hash in Firestore matches the hash of your password
- **Role not recognized**: Ensure role is exactly `doctor` or `compounder` (case-sensitive)

