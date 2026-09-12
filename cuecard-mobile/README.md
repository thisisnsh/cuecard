# CueCard Mobile

CueCard Teleprompter keeps your speaker notes visible above any app, so you can stay on script without switching screens. Whether you’re recording a video, presenting, or speaking live, your notes flow with you wherever you go.

## Bundle IDs

| Platform | Bundle ID |
|----------|-----------|
| iOS | `com.thisisnsh.cuecard.ios` |
| Android | `com.thisisnsh.cuecard.android` |

## Firebase Setup

Both apps require Firebase configuration files — Analytics and Crashlytics only,
there is no sign-in and no account. Download these from the
[Firebase Console](https://console.firebase.google.com):

### iOS Setup

1. Go to Firebase Console → Project Settings → Your Apps
2. Add an iOS app with bundle ID: `com.thisisnsh.cuecard.ios`
3. Download `GoogleService-Info.plist`
4. Replace `ios/CueCard/CueCard/GoogleService-Info.plist` with the downloaded file

### Android Setup

1. Go to Firebase Console → Project Settings → Your Apps
2. Add an Android app with package name: `com.thisisnsh.cuecard.android`
3. Download `google-services.json`
4. Replace `android/app/google-services.json` with the downloaded file

## Prerequisites

### iOS Development
- macOS
- Xcode 15.0+
- iOS 17.0+ deployment target
- Apple Developer account (for device testing)

### Android Development
- Android Studio Hedgehog (2023.1.1) or newer
- JDK 17
- Android SDK 34
- Min SDK: 26 (Android 8.0)

## Building

### iOS

```bash
# Open in Xcode
open ios/CueCard/CueCard.xcodeproj

# Or build from command line
cd ios/CueCard
xcodebuild -scheme CueCard -destination 'platform=iOS Simulator,name=iPhone 15 Pro'
```

### Android

```bash
# Open in Android Studio
open -a "Android Studio" android/

# Or build from command line
cd android
./gradlew assembleDebug
```