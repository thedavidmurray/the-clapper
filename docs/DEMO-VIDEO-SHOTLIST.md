# The Clapper — App Review Demo Video Shot List (Guideline 2.1 fix)

**Why:** Apple rejected v1.0 (build 4) under **Guideline 2.1 – Information Needed**, asking for a
demo video of the app on a **physical iOS device** showing **all features + all permission prompts**.
Submission ID `3ab390fd-2ba3-4c80-9b52-ccce4a57b1bc`. No code change / no new build needed — build 4
stays. This video is the entire fix.

## Hard requirements (Apple will re-reject if any are missing)
- **Physical iPhone**, not simulator. (iOS Control Center → Screen Recording captures it.)
- Show **every permission request prompt** as it appears (microphone, camera).
- Show **every feature** actually working — especially the gesture detection the reviewer couldn't reproduce.
- Keep it continuous/one-take if possible. ~60–120s is plenty.

## Setup before recording
1. Install **build 4 (v1.0)** on the iPhone — via TestFlight (build 4 is already uploaded) or Xcode→device.
2. **Delete the app first** if previously installed, so the permission prompts appear fresh on camera.
3. Quiet-ish room so the double-clap registers cleanly.
4. Start the iOS screen recording, THEN open the app.

## Shot sequence (narrate or on-screen caption each step)
1. **Launch** the app from the home screen (shows it's a real device + app icon).
2. **Microphone permission** — tap **Start Listening**; the iOS mic permission prompt appears →
   tap **Allow** (capture the prompt on screen).
3. **Core gesture** — with listening active, **clap twice**. Show the app detecting the double-clap
   (the on-screen detection indicator / triggered action firing). Do it **twice** so it's unambiguous.
4. **Camera tab** — navigate to the Camera tab.
5. **Camera permission** — trigger the camera; the iOS camera permission prompt appears → **Allow**
   (capture the prompt).
6. **Gesture-triggered recording** — demonstrate the gesture starting/stopping a recording. Show the
   resulting state (recording indicator, saved clip, whatever the UI shows).
7. **Any remaining features/tabs/settings** — briefly visit each so "all features" is satisfied.
8. End on the main screen.

## After recording — host it (David)
Put the file somewhere with a **stable, openable link** (no login wall for the reviewer):
- YouTube **unlisted**, or
- Google Drive with link-sharing "anyone with link → viewer", or
- any direct-download URL.

Then **send Claude the URL** → Claude will:
1. PATCH the ASC App Review Information **Notes** field to prepend the demo-video link
   (reviewDetail id `9f61c2a0-ef45-4666-9865-399c8632bde7`).
2. Draft the Resolution Center reply to Apple (David posts it in ASC web — the API can't post review messages).
3. Walk through the resubmission of build 4.

## Draft reply to Apple (for the Resolution Center, after the link is in Notes)
> Hello, thank you for the review. We've added a link to a demo video in the Notes field of the
> App Review Information section. The video was screen-recorded on a physical iPhone and demonstrates
> all features and permission requests: microphone permission and double-clap gesture detection, and
> camera permission with gesture-triggered recording. Please let us know if anything else is needed.
