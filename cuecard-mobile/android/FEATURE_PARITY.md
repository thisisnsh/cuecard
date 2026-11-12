# Android feature parity

Source review against the iOS app at commit `ade4e2b` (iOS 1.15.1), for
Android **1.0.0 (16)**. This compares user-facing capabilities;
it is not a claim that every device and platform integration was exercised.

| Area | Android status |
| --- | --- |
| Library | Opens on a library of scripts and decks, with the mode menu, collection chips (All, each collection with its count, + to make one; touch and hold to rename or delete), search, sort by date edited, date created or title, date sections, the open script or draft at the top, take thumbnails, swipes (delete; add to collection), and a touch-and-hold menu (open, rename, duplicate, add to collection, share, delete). Pitch, Talks, Reel and Shorts are made once. Reopens on the editor if it was left there. |
| Writing | Both modes, independent drafts, cues, bold/italic, anchors, images and card limits are present. The editor has a back button to the library, Save at the top while there are changes, ⋮ with Save, Save as New and Version History, and a status line with the title (tap to rename), Unsaved/Saved and the version (tap for history). Titles are kept to 40 characters; longer saved ones are shortened once at a word. |
| Notes and storage | Saved scripts keep their collection. The storage folder keeps the collections in `.cuecard-library.json`, the same file iOS writes. Importing keeps the file as a script in the collection shown and opens it. A banner says scripts aren't backed up until a folder is chosen, and comes back every tenth open after Not Now. |
| Versions | Saved versions, comparisons and restoration are present. |
| Teleprompter | Header with Close, the timer (centered while the buttons are hidden) and the camera; footer with the anchors at the edges and the floating window, Play and Restart together. The end of the script counts as the last anchor. Fades match the editor's. Settings and Help are no longer in the teleprompter or cards. |
| Floating window | Android picture-in-picture provides playback controls, timer, images, separate text sizing and aspect ratio. It stays disabled while the camera is open. |
| Cards | Swipe/button navigation, progress, images and count-up/count-down timer are present. Next fills the row beside Back. |
| Camera | Floating movable/resizable preview, front/back switching, zoom, recording, pause/resume, gallery saving and optional teleprompter synchronization are present. Text Above Camera draws the script, or the top card's words, over the camera; off, the camera covers them. Resolution, frame rate, HDR, stabilization and front-camera mirroring are chosen in Settings, offered as the device's cameras support them. |
| Takes | Per-script discovery, playback, tags, notes, favorites and deletion are present. The library shows each script's takes. The player has Delete at the top and the heart beside Tags and Notes below. Android gallery favorites require Android 11 or newer. |
| Settings | One screen from the library and the editor: Teleprompter, Camera, Cards, Language, Share and Review, Theme, then Advanced with Reset to Defaults. Every row has a line on what it does. |
| Help and onboarding | Welcome/sample scripts, a Library help page, sections matching iOS (Library & Saving with collections, privacy and storage; video settings; reading over the camera), ranked word search showing each result's section, language settings, sharing, reviews and remote notices. Both apps offer English, Spanish, French, Brazilian Portuguese and Russian. |

## Platform-specific differences retained

- Apple Intelligence: Suggestions AI, Help AI and Follow Me AI, with their
  Settings switches and feedback sheets, are not on Android.
- Apple Watch companion, wrist controls and offline watch decks.
- ActivityKit Lock Screen/Dynamic Island cards and WidgetKit controls.
- iPhone Action Button and App Intents.
- Apple Photos album creation and multiple-album membership. Android takes
  remain in the device's video library and use its native permission flows.
- Codec choice, Apple Log and cinematic stabilization: CameraX picks the codec,
  and offers stabilization on or off.
- The iCloud Drive storage note. Android names the storage folder instead.
- Platform-native review prompts, language settings and camera/library APIs.

## Release metadata

`versionCode` advances from 15 to 16; `versionName` remains `1.0.0`.
`assets/WhatsNew.json` and all release-note translation arrays are empty, so
neither launch nor Help offers a What's New entry.

## Verification

Debug APK build, Kotlin compilation of the instrumentation tests and lint
(no errors) passed with JDK 17 from Android Studio. The instrumentation tests
and the app itself were not run for this change.

Run from this directory with JDK 17 or newer and a running Android emulator:

```sh
./gradlew :app:assembleDebug :app:lintDebug :app:connectedDebugAndroidTest
```

Camera capture quality, the device's video formats, OEM gallery behavior and
clipboard transfers to third-party apps still need physical-device release QA.
