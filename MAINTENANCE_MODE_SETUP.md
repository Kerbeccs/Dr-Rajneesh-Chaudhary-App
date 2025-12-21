# 🔧 Maintenance Mode Setup Guide

## Quick Setup

### 1. Create Firestore Document

**Path:** `app_config/maintenance`

**Document Structure:**
```json
{
  "enabled": false,
  "message": "Custom maintenance message (optional)",
  "minVersion": "1.0.0"
}
```

### 2. Enable Maintenance Mode

**Via Firebase Console:**
1. Go to Firestore Database
2. Create collection: `app_config`
3. Create document: `maintenance`
4. Add fields:
   - `enabled` (boolean): `true`
   - `message` (string): Your custom message
   - `minVersion` (string, optional): Minimum app version required

**Example:**
```json
{
  "enabled": true,
  "message": "We are performing scheduled maintenance. Please check back in 30 minutes.",
  "minVersion": null
}
```

### 3. Disable Maintenance Mode

Simply set `enabled` to `false`:
```json
{
  "enabled": false
}
```

## Use Cases

### Scheduled Maintenance
```json
{
  "enabled": true,
  "message": "Scheduled maintenance from 2 AM to 4 AM. The app will be back shortly.",
  "minVersion": null
}
```

### Critical Bug Fix
```json
{
  "enabled": true,
  "message": "We are fixing a critical issue. Please update the app to continue.",
  "minVersion": "1.0.1"
}
```

### Force App Update
```json
{
  "enabled": true,
  "message": "Please update to the latest version for new features and bug fixes.",
  "minVersion": "1.1.0"
}
```

## How It Works

1. **App Startup:** Splash screen checks maintenance status from Firestore
2. **If Enabled:** Shows maintenance screen instead of login
3. **If Disabled:** App continues normally
4. **Version Check:** If `minVersion` is set, users with older versions see update button

## Testing

1. **Enable maintenance mode** in Firestore
2. **Close and reopen the app**
3. **Verify maintenance screen appears**
4. **Disable maintenance mode**
5. **Verify app works normally**

---

**Note:** Maintenance mode is checked every time the app starts. Changes in Firestore take effect immediately on next app launch.

