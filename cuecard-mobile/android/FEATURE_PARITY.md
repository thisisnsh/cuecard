# Android feature parity

Source review against the iOS app at commit `e5e0924` (iOS 1.13.0), for
Android's first release, **1.0.0 (14)**. This compares user-facing capabilities;
it is not a claim that every device and platform integration was exercised.

| Area | Android status |
| --- | --- |
| Writing | Both modes, independent drafts, cues, bold/italic, select all, anchors, images and card limits are present. Added image clipboard paste and copying individual images to other apps. |
| Notes | Save, rename, delete, search, mode filters, current-note marker and unsaved-change confirmation are present. |
| Files | Text/RTF import, text/TextPack sharing, notes-folder synchronization and image storage are present. |
| Versions | Saved versions, comparisons and restoration are present. |
| Teleprompter | Automatic/manual scrolling, speed, countdown, restart, draggable reading guide, anchor navigation and both mirror directions are present. |
| Floating window | Android picture-in-picture provides playback controls, timer, images, separate text sizing and aspect ratio. It stays disabled while the camera is open. |
| Cards | Swipe/button navigation, progress, images and count-up/count-down timer are present. |
| Camera | Floating movable/resizable preview, front/back switching, zoom, recording, pause/resume, gallery saving and optional teleprompter synchronization are present. |
| Takes | Per-script discovery, playback, tags, notes, favorites and deletion are present. Fixed reopening a script erasing its previous recording sessions. Android gallery favorites require Android 11 or newer. |
| Preferences | Per-mode sizes/colors/timers, theme, advanced settings and resets are present. |
| Help and onboarding | Welcome/sample scripts, searchable help, language settings, sharing, reviews and remote notices are present. Both apps currently offer English, Spanish, French, Brazilian Portuguese and Russian. |

## Platform-specific differences retained

- Apple Watch companion, wrist controls and offline watch decks.
- ActivityKit Lock Screen/Dynamic Island cards and WidgetKit controls.
- iPhone Action Button and App Intents.
- Apple Photos album creation and multiple-album membership. Android takes
  remain in the device's video library and use its native permission flows.
- Platform-native review prompts, language settings and camera/library APIs.

## Release metadata

`versionCode` advances from 13 to 14; `versionName` remains `1.0.0`.
`assets/WhatsNew.json` and all release-note translation arrays are empty, so
neither launch nor Help offers a What's New entry for the first release.

## Regression coverage

`ScriptClipboardTest` exercises actual Compose editing and the Android
clipboard: normal text replacement, image/source-URL paste, multiple images
in cards, copying readable image data, pasting copied script tags, mixed text
and images, unavailable images, and the empty first-release notes.
`TakeStoreTest` checks that reopening and switching scripts retains previous
recording sessions and take annotations.

All eight instrumentation tests passed on the Android 16 (API 36.1) emulator.
Debug and minified release APK builds passed. Lint reported no errors; existing
warnings remain. The release APK is unsigned, and Crashlytics mapping upload
was excluded from the local release-build check.

Run from this directory with JDK 17 or newer and a running Android emulator:

```sh
./gradlew :app:assembleDebug :app:lintDebug :app:connectedDebugAndroidTest
```

Camera capture quality, OEM gallery behavior and clipboard transfers to
third-party apps still need physical-device release QA.
