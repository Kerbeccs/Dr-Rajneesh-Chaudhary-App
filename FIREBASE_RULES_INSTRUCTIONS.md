# Firebase Security Rules Instructions

## How to Fix the Permission Error

You're encountering a Firebase permission error when trying to access the Firestore database. This is because the security rules in your Firebase project are too restrictive. Follow these steps to fix it:

1. **Go to the Firebase Console**
   - Visit [https://console.firebase.google.com/](https://console.firebase.google.com/)
   - Select your project

2. **Navigate to Firestore Database**
   - In the left sidebar, click on "Firestore Database"
   - Click on the "Rules" tab

3. **Update the Security Rules**
   - Replace the current rules with the following:

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

4. **Publish the Rules**
   - Click the "Publish" button to apply the new rules

5. **Restart Your App**
   - Close and restart your Flutter app

## What These Rules Do

These rules allow any authenticated user to read and write to any document in your Firestore database. This is suitable for testing but **not recommended for production**. 

## For Production

For production, you should use more restrictive rules like:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Allow users to read and write their own documents
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
    
    // For doctor access to all patients
    match /users/{userId} {
      allow read, write: if request.auth != null && 
        get(/databases/$(database)/documents/users/$(request.auth.uid)).data.userType == 'doctor';
    }
    
    // Allow patients to create and read their own reports
    match /reports/{reportId} {
      allow read: if request.auth != null && 
        resource.data.patientId == request.auth.uid;
      allow create: if request.auth != null && 
        request.resource.data.patientId == request.auth.uid;
    }
    
    // Doctor can read all reports
    match /reports/{reportId} {
      allow read, write: if request.auth != null && 
        get(/databases/$(database)/documents/users/$(request.auth.uid)).data.userType == 'doctor';
    }
  }
}
```

These rules ensure that:
- Patients can only access their own data
- Doctors can access all patient data
- Reports can only be accessed by the patient who created them or by doctors 