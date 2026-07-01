# Audit — The Clapper (iOS, read-only, Fable 5)

> Run 2026-07-01 via 14-agent dynamic workflow (5 parallel pass-groups + adversarial verification of every
> HIGH/CRITICAL finding) per `AUDIT_RUBRIC_FABLE.md`. 54 raw findings → 1 refuted → **53 stand**.
> Codebase state: master @ `0fea4a1` (build 8 — DSP classifier, SoundAnalysis removed).

## Scorecard

| Pass | Score | One-line note |
|---|---|---|
| 0–1 Architecture & memory | 3.5/5 | Map confirmed; no God object; retain-cycle hygiene genuinely good ([weak self] throughout); defects are stale-state start guards + nested-ObservableObject gaps + reintroduced dead code |
| 2 Concurrency & lifecycle | 2.5/5 | Main-thread hygiene on the audio path is solid; lifecycle robustness is not (no interruption handling, unguarded recording start, unbalanced teardown) |
| 3 Security & privacy | 3.5/5 | Data privacy exemplary (0 secrets, 0 networking, nothing persisted); permission handling FAILS the exact axis of the 2.1 rejection |
| 4 Logic & robustness | 2/5 | Zero Swift force-unwrap crash surfaces; ONE reachable ObjC exception (CRITICAL); several swallowed errors |
| 5–6 Quality & regression | 3/5 | Small/clean codebase, no log leakage; ZERO XCTest targets; git history strengthened (not weakened) critical paths |

## Top findings (ranked)

1. **[CRITICAL]** Gesture-mapped `movieOutput.startRecording` fires on a non-running capture session — `CameraService.swift:93`. Reviewer path: launch → grant mic → stay on Monitor tab → double-clap → `NSInvalidArgumentException` (no active connections). *The* review-crash.
2. **[HIGH]** No `AVAudioSession` interruption/route-change/engine-config-change handling anywhere — `AudioSessionService.swift` / `AudioMonitorService.swift`. Phone call/Siri/alarm kills the engine; UI stays "Listening" forever; recovery blocked by the stale `isListening` guard.
3. **[HIGH]** Mic-permission-denied = permanent silent dead state — `ClapperViewModel.swift:121`. No denied UX, no Settings deep-link. Guideline 2.1 re-rejection risk.
4. **[HIGH]** Camera authorization never checked (`grep AVCaptureDevice.authorizationStatus` = 0 hits) — `CameraService.swift:26`. Prompt fires at app launch (eager init), denied → black preview + reachable exception on gesture record.
5. **[HIGH]** `startListening` double-run: `isListening` guard is set async; `.task` + `scenePhase .active` can both fire → second live `AVAudioEngine` leaks with mic held — `AudioMonitorService.swift:36`. (One variant of this was refuted by the verifier as sub-frame; the dual-auto-start same-runloop variant stands.)
6. **[HIGH]** `CameraService.setupSession` fails silently once at init; no retry when permission later granted; no runtimeError/interruption observers — permanent dead camera — `CameraService.swift:31`.
7. **[MEDIUM]** Debug HUD ("lvl · onsets", marked *Remove before App Store submit*) still ships in the Camera UI — `CameraView.swift:77`.
8. **[MEDIUM]** `durationTimer` never invalidated on abnormal recording finish — timer leak + corrupted duration — `CameraService.swift:193`.
9. **[MEDIUM]** Double haptic per mapped gesture (VM sink + ActionDispatcher both fire `gestureConfirmed`) — `ClapperViewModel.swift:75`.
10. **[MEDIUM]** Photo-library saves use nil completion targets — denial/failure silently loses the user's recording; photo path also calls UIKit save off-main — `CameraService.swift:149/220`.
11. **[MEDIUM]** Temp `.mov` files (raw + trimmed) never deleted — `temporaryDirectory` grows every gesture recording — `CameraService.swift:89`.
12. **[MEDIUM]** `fileOutput(didFinishRecordingTo:)` discards recordings whenever `error != nil`, ignoring `AVErrorRecordingSuccessfullyFinishedKey` (disk-full/interruption clips are usually playable) — `CameraService.swift:197`.
13. **[MEDIUM]** `AppStoreMetadata.md` still describes the removed SoundAnalysis ML pipeline — resubmission mismatch risk — `AppStoreMetadata.md:91`.
14. **[MEDIUM]** Camera start/stop race: async `startRunning` can land after `stopSession`'s guard — camera stays on while user is elsewhere (privacy optics) — `CameraService.swift:69`.
15. **[MEDIUM]** Zero XCTest targets — no regression tests for classifier thresholds, gesture windows, or permission paths.

(Plus ~16 LOW / 13 INFO: dead SoundClassifierService still compiled, `lastClassification` UI unreachable, unsynchronized threshold vars main→audio-thread, `switchCamera` unguarded mid-recording, stale "Tap to start listening" copy, formatDuration duplicated with divergent formats, swiftlint line-length in newest code, deinit-less timers, session-active-after-failed-start, UIBackgroundModes audio invites 2.5.4 scrutiny.)

## Privacy verdict

**NO mic audio or camera footage leaves the device — CONFIRMED (positive finding).**
Trace: mic buffers → in-memory RMS/peak/ZCR scalars + 64-pt waveform → UI only; never written, never logged.
Recordings: `temporaryDirectory` → (optional trim) → user Photo Library only. Zero `URLSession`/`URLRequest`/
analytics; all 21 Swift files import Apple frameworks only; no vendored/third-party code; 0 secrets in
source (grep verified). Weakness is at-rest housekeeping (temp files never cleaned), not exfiltration.

## Permission-handling verdict

**FAIL (review-critical — the 2.1 rejection axis).** Usage strings (mic/camera/photo-add) exist and are
honest. But: mic-denied → silent dead state, no Settings path; camera authorization never checked, prompt
fires at launch instead of in context, denied path = black preview + crash surface; photo-add failures
silently swallowed.

## Concurrency verdict

No off-main `@Published`/UI mutation on the audio path (tap callbacks hop to main; all VM sinks
`receive(on: .main)`); one off-main UIKit call on the photo-save path (`CameraService.swift:220`).
No retain cycles on capture sessions. Teardown incomplete: no interruption/route-change observers,
`durationTimer` leak on abnormal finish, `activate()/deactivate()` unbalanced on engine-start failure,
no `deinit` on timer-owning services. Double-start leak possible via dual auto-start triggers.

## Crash-surface list

Zero literal `try!`/`as!`/`.first!`/force-unwraps in audio/camera/dispatch paths (grep-verified). The one
`fatalError` (`CameraPreviewView.swift:25`) is unreachable (`layerClass` override). `PercussiveClassifier`'s
`count > 8` guard fully protects all buffer accesses. **The one reachable crash is ObjC:**
`AVCaptureMovieFileOutput.startRecording` on a non-running session (`CameraService.swift:93`) — reachable
by double-clapping on the Monitor tab with default mappings.

## Coverage gaps & NOT REVIEWED

- No dynamic analysis (rubric forbids building/running) — findings are static-analysis only.
- `fastlane/`, `build/`, provisioning material: out of scope per §0 (by design).
- ASC listing state: out of scope per §0.

## Prior-audit reconciliation

- `app-store-submission-readiness-2026-06-13.md`: claims about the two-stage SoundAnalysis pipeline are
  **stale** (removed in build 8). Privacy claims **confirmed**. Permission-UX readiness claims **refuted**
  (denied paths unhandled).
- `AppStoreMetadata.md`: HOW IT WORKS + review notes **stale** — describe the removed ML pipeline; must be
  rewritten before resubmission.
- Commit `3cbb0e0` removed 27 unused declarations; builds 6–8 **reintroduced** a dead-code cluster
  (SoundClassifierService + unreachable classification UI).
- Pass 6 positive: git history **strengthened** critical paths over time (permission strings added, weak
  self preserved, no sensitive logging introduced).

## Meta

Rubric §5 sanctions writing this file; the workflow's agents ran fully read-only (findings via structured
output) and the orchestrator performed this single write — the "sole sanctioned write" property holds.
