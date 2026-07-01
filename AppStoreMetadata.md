# The Clapper - App Store Metadata

## App Name
The Clapper - Gesture Remote

## Subtitle (30 chars max)
Audio-Reactive Phone Control

## Category
Primary: Utilities
Secondary: Photo & Video

## Price
Free (v1 launch)

## Bundle ID
com.edgeless.theclapper

## Description (4000 chars max)

The Clapper turns sound into action. Clap to start recording. Snap to toggle your flashlight. Triple-clap to take a photo. Set up your shot, walk into frame, and clap to roll.

Built for solo content creators, photographers, athletes, cooks, and anyone who needs hands-free phone control.

HOW IT WORKS

The Clapper uses a two-stage audio detection pipeline:
- Stage 1: Ultra-fast transient detection catches the moment you clap (under 10ms)
- Stage 2: Apple's on-device ML confirms it was actually a clap, not a door slam or cough

This dual-layer approach means near-zero false positives with sub-second response time. All processing happens on-device. No cloud. No data leaves your phone.

GESTURE VOCABULARY

- Single Clap: Configurable action
- Double Clap: Start/stop video recording (default)
- Triple Clap: Take a photo (default)
- Finger Snap: Toggle flashlight (default)

Every gesture maps to any action. Configure it your way in Settings.

BUILT-IN CAMERA

Full camera view with live preview, front/back switch, and manual record button. The Clapper listens while you record, so you can stop recording with another clap.

USE CASES

- Solo video: Set up tripod, frame shot, walk in, clap to record
- Cooking: Hands covered in flour? Clap to start your timer
- Sports: Start your stopwatch without touching your phone
- Accessibility: Control your phone with sound when touch isn't an option
- Presentations: Advance slides hands-free

DESIGN

Dark, minimal interface built on the Edgeless design system. Real-time waveform visualization shows exactly what the app hears. Haptic feedback confirms every detected gesture.

PRIVACY

- All audio processing happens on-device
- No audio is recorded, stored, or transmitted for detection
- Camera recordings save directly to your photo library
- No analytics, no tracking, no accounts

## Keywords (100 chars max)
clap,gesture,remote,hands-free,recording,camera,sound,audio,accessibility,timer

## Support URL
https://edgelesslab.com/support

## Marketing URL
https://edgelesslab.com/the-clapper

## Privacy Policy URL
https://edgelesslab.com/privacy

## What's New (v1.0)
Initial release. Clap detection, photo capture, video recording, stopwatch timer, flashlight toggle, configurable gesture mapping.

## Rating
4+ (No objectionable content)

## Screenshots Needed
1. Home screen - waveform visualization, "Listening" state
2. Camera view - full screen preview with gesture overlay
3. Settings - gesture-to-action mapping configuration
4. Gesture detected - clap recognized with confidence badge
5. Recording active - camera view with red recording indicator

## App Review Notes
This app requires microphone access for audio gesture detection and camera access for video recording. Detection is pure on-device signal processing (amplitude onset detection plus a small DSP clap/snap classifier built on Apple's Accelerate framework — zero-crossing rate and spectral energy). No machine-learning models are used or included, no audio is recorded or stored, and no data is transmitted off-device.

To test: Grant microphone permission — the app starts listening automatically. Clap twice to trigger the double-clap gesture (default: start/stop recording — visible on the Camera tab). Clap once or three times for the other gestures, or snap your fingers for the snap gesture. Gesture-to-action mappings are configurable in Settings. If microphone or camera access is denied, the app shows an explanation with a link to Settings.
