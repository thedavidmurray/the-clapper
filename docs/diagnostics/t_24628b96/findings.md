# Clapper detector diagnosis — t_24628b96

## Decision and scope

A reproducible detector defect is fixed locally: whole-tap RMS discards short attacks before the gesture/action pipeline can run. This explains a concrete failure mode, **not yet David's exact physical-device failure**. Do not release, submit, cancel, or replace any ASC candidate. Physical-device QA and independent review remain required; t_296cd027 stays held.

Tested baseline: free build-14 source `1506e398b357ea4d0b19f3742cd015be2446a5f1`. This is the free candidate identified in the existing release-readiness report. The audio-monitor and view-model files are identical to those in the canonical dirty checkout at `c7dbb8d939cd9bfab0950e52cbd815f019a22a78`; unrelated paid-update/StoreKit working changes were not copied or modified. The July ASC upload cannot be matched byte-for-byte to this local source from available receipts.

Remote `master` is still `ed451adab9423e0dc179b7ba7f8e61bda52620c0` (build 11), confirmed by fetch and GitHub API. A PR against master also carries four already-existing free/build-12–14 and test-bundle prerequisite commits. Review that baseline separately from this task's detector/test/evidence commit. No paid StoreKit changes are included.

## Root cause and source trace

`AudioMonitorService.processBuffer` originally computed one RMS over the entire delivered buffer, subtracted the previous smoothed RMS, and required the derivative to exceed the sensitivity threshold. The waveform uses peak magnitude, so it can visibly spike while detection fails. Existing tests began at `onTransientDetected`, bypassing the flawed PCM stage.

Actual synthetic PCM fixture (not a recorded human clap): 48 alternating ±0.3 samples in 1024 samples at 48 kHz. Computed with Python:

- Whole-buffer RMS: `0.06495190528383289`.
- Default sensitivity derivative threshold: `0.085`; minimum amplitude: `0.046`.
- With an initial zero noise floor, the derivative fails `0.06495 > 0.085`.
- At a 4096-frame tap it falls to `0.032475952641916446`, below both gates.
- Over a 96-frame / 2 ms window, RMS is `0.21213203435596426`.

Red XCTest executed the actual `processBufferExternal` implementation and actual view-model bindings, not a rewritten detector. It produced 10 assertion failures in two failing test cases (five test cases total): six tap-size/window-position misses, followed by no onset/gesture/timer in the integration test.

Core source route: `AudioMonitorService.transientDetected` → `ClapperViewModel.setupBindings` → `GestureRecognizerService.onTransientDetected` → 0.65-second sequence timer → `gestureRecognized` → `ActionDispatcher.dispatch`. The integrated test maps single clap to the real stopwatch and verifies `isTimerRunning`; it does not claim a camera recording or Photos save.

## REA / Ghidra evidence on built Release Mach-O

REA 6.3.0, Ghidra 12.1.4, Temurin full JDK 21.0.12.1. Ghidra/JDK were absent at task start; downloaded into the task workspace. Built the native mac_arm_64 tools with the release's documented `support/gradle/gradlew --no-daemon --max-workers=4 -g <workspace>/tools/gradle-cache buildNatives`.

The universal simulator executable must be thinned with `xcrun lipo -thin arm64`; REA explicitly rejected the universal input instead of silently choosing a slice. Native addresses below are unslid addresses in these local simulator binaries, not device/crash addresses.

- Baseline arm64 slice SHA-256: `95ef7bf2b808da74c33b3eac7b12153e128351543c745492db34fef9532f00f3`.
- Baseline `processBuffer` entry: `0x100023e18`, body `0x100023e18–0x100024273`.
- Ghidra pseudocode calls `_vDSP_measqv(..., frameLength)` once, stores `fVar21 * 0.3 + fVar23 * 0.7` into `smoothedRMS`, then tests `onsetThreshold < fVar21 - fVar23` and `minimumAmplitude < *pfVar16` before `PassthroughSubject::send`. No short-window RMS loop exists.
- Baseline downstream symbols: recognizer `0x100024444`, dispatcher `0x10002d29c`; source bindings plus the executed integration test establish the dynamic connection, not a claimed direct native call chain.
- Fixed arm64 slice SHA-256: `dbb7623c726173f3f4f7908ffb6ed171b9b0a57c2914d962da3d5f442db71ed8`.
- Fixed `processBuffer` entry: `0x100023e24`; pseudocode shows `sampleRate * 0.002`, a loop, and a second `_vDSP_measqv` measuring the bounded windows.

`baseline-function.json` and `fixed-function.json` retain exact selected REA fields and pseudocode; they are explicitly excerpts, not canonical complete REA Evidence bundles. Raw complete output, progress logs, thin binaries and XCTest bundles are retained in the task evidence archive. `hash-manifest.json` binds selected raw evidence and source files to their actual bytes.

No supplied crash log/sysdiagnose was available. A filename search of `/Users/djm/Library/Logs/DiagnosticReports` found no `*Clapper*` files. The conventional `CrashReporter/MobileDevice` folder is absent. These boundaries are not evidence that the device never crashed. No crash address or exception was invented.

## Fix and checks

- Preserve full-buffer RMS/peak/waveform for the UI.
- Detect against 2 ms RMS windows and the existing smoothed noise floor, with the existing sensitivity and debounce settings.
- Ignore empty buffers; reset onset history when listening stops.
- Add real PCM tests for 1024/4096 taps and boundary positions, silence/low-level noise, sustained signal/debounce, stop/reset, empty buffers, and PCM→view-model→recognized-clap→mapped-stopwatch.

The 2 ms analysis window does not make callback delivery 2 ms: latency still includes the engine's buffer and the gesture's 0.65-second grouping wait. This is an energy/onset detector, not a trained clap classifier. Physical precision/recall is unmeasured.

## Exact executed verification

Working directory for commands: task workspace; repository is its `source/` worktree. Raw paths below are in the attached evidence archive under `evidence/`.

Baseline Release build:

```sh
xcodebuild -project source/TheClapper.xcodeproj -scheme TheClapper -configuration Release -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath evidence/baseline-release CODE_SIGNING_ALLOWED=NO build
```

Result: exit 0, BUILD SUCCEEDED. Before the fix, the focused PCM test run returned xcodebuild exit 65 and logged:

```text
CLAPPER_PIPELINE: PCM(48/1024 frames, amplitude=0.3) -> onset=0 -> gesture=nil -> timerRunning=false
```

Final exact-source Release suite (ENABLE_TESTABILITY is needed for `@testable`, retaining Release optimization):

```sh
xcodebuild -project source/TheClapper.xcodeproj -scheme TheClapperTests -configuration Release -destination 'platform=iOS Simulator,id=9FB52DEE-23B0-43F1-B9BD-111ACE7EE6F5' -derivedDataPath evidence/release-tests -resultBundlePath evidence/final-release-tests.xcresult CODE_SIGNING_ALLOWED=NO ENABLE_TESTABILITY=YES test
xcrun xcresulttool get test-results summary --path evidence/final-release-tests.xcresult --format json
```

Result: exit 0, **25 tests passed, 0 failed, 0 skipped**, summary `result: Passed`. Output includes:

```text
CLAPPER_PIPELINE: PCM(48/1024 frames, amplitude=0.3) -> onset=1 -> gesture=Optional(TheClapper.GestureType.singleClap) -> timerRunning=true
```

Prior Debug full run passed 24/24 before adding the stop/reset case; the final 25-test run is Release. Final normal Release build (without testability override) also returned exit 0 / BUILD SUCCEEDED, followed by successful simulator install and launch. The initial launch showed the truthful mic-denied UI. Granting simulator microphone permission with `xcrun simctl privacy <UDID> grant microphone com.edgeless.theclapper` and relaunching showed “Listening for gestures” / “Listening” (`microphone-granted.png`). That UI is startup evidence only; the XCTest output is the PCM/action proof. No claim is made that ambient host audio or a real clap was captured.

Native analysis commands:

```sh
export GHIDRA_INSTALL_DIR=<workspace>/tools/ghidra_12.1.4_PUBLIC
export JAVA_HOME=<workspace>/tools/java/jdk-21.0.12.1+1/Contents/Home
export PATH="$JAVA_HOME/bin:/Users/djm/.hermes/tools/node-26.7.0-darwin-arm64/bin:$PATH"
xcrun lipo evidence/baseline-release/Build/Products/Release-iphonesimulator/TheClapper.app/TheClapper -thin arm64 -output evidence/baseline-arm64.macho
env HOME=/Users/djm npm_config_cache=/Users/djm/.npm npx --offline --yes rea-agents@6.3.0 function evidence/baseline-arm64.macho 0x100023e18 --provider ghidra --format json
env HOME=/Users/djm npm_config_cache=/Users/djm/.npm npx --offline --yes rea-agents@6.3.0 function evidence/final-fixed-arm64.macho 0x100023e24 --provider ghidra --format json
```

Both thin-binary function analyses returned exit 0, provider `ghidra`, version `12.1.4`. `git diff --check` and `plutil -lint TheClapper.xcodeproj/project.pbxproj` pass.

## Still required from David / release gate

1. Reproduce the original symptom with exact installed version/build, foreground tab, permissions, mapping, distance/room, and any crash/sysdiagnose. Match that binary/source before claiming this fixes the reported device failure.
2. Acoustic QA on the physical phone: single/double/triple claps, varied distances and sensitivity, quiet/noisy rooms, speech/music/impacts as negatives. Measure missed and false detections; shorter windows can change false-positive behavior.
3. Camera-tab microphone/capture coexistence, front/rear flip, photo save, video start/stop and clap trimming; foreground/background mic teardown, route changes and interruptions.
4. Independent code review and exact-head hosted CI where applicable. The existing paid-update StoreKit/release gates remain untouched.

The paired phone is visible via devicectl, but no physical acoustic/camera QA is claimed here. No App Store operation was performed.

## Reusable finding / positive definition of correct

Per [[context-engineering-positive-definition-good-work]], this implementation is checkable through actual failed-then-passing PCM tests, native evidence tied to hashed built binaries, a real mapped action changing state, explicit source/production identity boundaries, and physical QA held rather than inferred from simulator output. Test the PCM entry point, not only handcrafted downstream onset events. Distinguish a reproducible contributor from an unconfirmed customer-specific root cause.

KB preflight: qmd initially failed under Node 20 (better-sqlite3 ABI mismatch); selecting the installed Node 26.7 runtime made it work. Both “Clapper audio detection” and “Clapper” returned no relevant hits. No shared `docs/projects/*clapper*` context was found. GitHub CLI initially appeared unauthenticated under the worker profile HOME; the existing default-user keyring login works with `HOME=/Users/djm` (no credentials read or modified).
