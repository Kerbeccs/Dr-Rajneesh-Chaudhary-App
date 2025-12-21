# Doctor Login Instructions

## How to Log In as a Doctor

1. **Use the Hardcoded Credentials**
   - Username: `DRJC`
   - Password: `DRJC01`

2. **What Happens Behind the Scenes**
   - When you log in with these credentials, the app will:
     - Create or authenticate a doctor account with Firebase Auth using email `doctor@example.com` and password `doctor123`
     - Set the `userType` field to 'doctor' in Firestore
     - Navigate to the Doctor Dashboard

## Debugging Information

We've added extensive debug print statements throughout the app to help diagnose any issues:

- In the `AuthViewModel` class:
  - The `loginAsDoctor` method now creates a new account if it doesn't exist
  - Debug print statements show the authentication process

- In the `LoginScreen`:
  - Debug print statements show the login attempt and navigation

- In the `DoctorDashboard`:
  - Added a card to display the doctor's information
  - Debug print statements show the current user

- In the `DoctorAppointmentsViewModel`:
  - Added checks to ensure the user is authenticated and has the 'doctor' userType
  - Debug print statements show the query process

- In the `DoctorAppointmentsScreen`:
  - Debug print statements show the UI building process and appointment data

## Firebase Security Rules

The current Firebase security rules allow any authenticated user to read and write to any document:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /{document=**} {
      allow read, write: if request.auth != null;
    }
  }
}
```

These rules are suitable for testing but should be replaced with more restrictive rules for production.

## Troubleshooting

If you encounter any issues:

1. **Check the Debug Console**
   - Look for error messages in the debug console
   - The debug print statements should help identify where the issue is occurring

2. **Verify Firebase Authentication**
   - Make sure the doctor account is created in Firebase Auth
   - Check that the `userType` field is set to 'doctor' in Firestore

3. **Check Firestore Security Rules**
   - Make sure the security rules allow the doctor to read and write to the necessary collections

4. **Clear App Data and Try Again**
   - Sometimes clearing the app data and trying again can resolve authentication issues 