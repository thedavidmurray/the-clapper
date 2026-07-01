# App Store Submission Readiness — 2026-06-13

State after recovery work on EDGA-8501 / EDGA-9712.

## Automation outcome
- Attempted simulated-device capture via `xcrun simctl io recordVideo`.
- Blocked by `xcrun simctl io recordVideo: Simulator does not support using the hardware screen recording API`.
- Conclusion: simulator path cannot produce footage accepted for Guideline 2.1.

## Completed
- Verified IPA exists and is signed:
  - `/Users/djm/claude-projects/products/the-clapper/build/TheClapper.ipa`
  - Built 2026-05-29 via `fastlane ios beta`
  - App Store Connect upload for TestFlight: successful
- Confirmed locally selectable physical device:
  - `Wavy Javy` / iPhone 14 Pro / hostname `Wavy-Javy.coredevice.local`
- Confirmed buildable project path:
  - `/Users/djm/claude-projects/products/the-clapper`
- Repaired deliverable blockers that were previously stalled:
  - physical demo plan
  - episode script
  - metadata repair for promotional_text length failure in fastlane release log
- Pre-staged submission metadata that uses the local promo text length and review instructions, now aligned with Review Notes wording in `clapper-physical-demo-episode.md`

## Blocked hardware capture runbook
1. Put the physical iPhone on the matte black surface used for the plan.
2. Install the app from TestFlight or Xcode if not present on device.
3. Record screen with built-in iOS recorder.
4. Capture shots:
   - launch
   - microphone permission grant
   - double clap -> remote control action
   - settings adjustment
   - natural close
5. Trim to 90-120 seconds.
6. Save as `Clapper_PhysicalDevice_Demo_20260613.mov`.
7. Upload to a shareable host:
   - Google Drive shareable link, or
   - YouTube unlisted preferred for Apple review
8. Update submission `3ab390fd-2ba3-4c80-9b52-ccce4a57b1bc` with the link and use the review notes text already prepared in episode markdown.
