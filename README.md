# Duet 0.5.1 · Native iPhone app

SwiftUI / UIKit throughout, without a web view or bundled HTML/JS/CSS. GitHub macOS builds an unsigned arm64 IPA for self signing. iOS 17 minimum; Xcode 26 supplies native Liquid Glass on iOS 26, with system Material on older versions.

## This revision

- System TabView and NavigationStack; restrained typography, consistent spacing and corner metrics; right swipe to pin, no home search or row chevrons.
- Chat opens at the latest message, preserves manual scroll position during replies, uses nearby circular avatars and small timestamps. Tap the header avatar for options and model selection.
- Per-chat wallpaper with crop position, zoom, blur, dimming and a wide adjustable header fade. Solid global backgrounds and theme colors remain available.
- Global system font or user-imported TTF/OTF, with native file provider coordination, validation and duplicate detection. No bundled artistic font preset.
- Separate private/group call names, editable role profiles and approved memories. Clearing messages preserves independently saved memories and unfinished drafts.
- Native camera and multi-photo picker; compact swipeable photo stacks and full screen zoomable gallery. The bridge accepts up to six compressed JPEG photos per message, keeps bytes out of history snapshots, and restores missing photo assets on sync.
- Explicit ordinary ChatGPT vs Codex model selection, dynamic model catalogs, default reasoning effort follows each model. No automatic fallback between allowance types.
- Per-chat/all history clearing also cancels queued replies and synchronizes deletion to the computer, including when offline. Old message UUID retries cannot resurrect cleared history.
- Idea/todo local scheduled reminders and AI reply notifications. Notification taps open the corresponding idea/message. iOS 26 continued processing and finite background time support an already-started reply; force-quit immediate delivery still needs an APNs service and is not implemented.

## Computer bridge

Own Windows computer and logged-in Edge must remain running. The separate Duet connector creates temporary unpersonalized chats and supplies only the selected channel context. It does not read browser login tokens. Application heartbeats and a watchdog recover suspended extension connections. A request already submitted with an unknown result is never automatically submitted again.

An optional Cloudflare temporary HTTPS/WSS entry supports the user's chosen remote access. Its public address changes after tunnel restart; scan the new pairing QR when that happens. Pairing tokens stay in the iPhone keychain and are excluded from this repository.

Ordinary GPT-6 text and phone delivery were verified on connector 0.2.8. The new 0.3 connector photo flow still requires the user's phone test; the user chose to keep the official browser extension's local-file permission disabled. Do not describe image understanding as verified before that test. Claude and ordinary document AI input remain unavailable. Selecting a file currently provides local Quick Look preview only and sending it produces an explicit unsupported-input error.

## Build and validation

Push to main triggers **Build Native iPhone IPA**. Download **Duet-native-ipa**, extract `Duet-Native-unsigned.ipa`, then self sign. Bundle ID remains `app.duet.preview`, version 0.5.1. Update over the existing installation to preserve app data.

The workflow validates native-only sources/IPA, compiles on macOS, runs storage/font/photo unit tests and iPhone simulator UI tests, and exports screenshots and failure diagnostics. Simulator testing does not replace physical-phone checks for camera, notification delivery, signing or real image analysis. Font test fixtures are in the test target only and are not bundled in the app.

0.5.1 removes the extra replying caption below bubbles and keeps an accessible typing indicator inside the empty reply bubble. The optional Duet connector 0.3.1 defaults to background tabs without browser focus; this has separate real-device verification.
