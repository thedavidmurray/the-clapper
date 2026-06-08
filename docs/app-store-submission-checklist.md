# The Clapper — App Store Submission Checklist

_Last verified: 2026-05-29. Source of truth for what is **automated** vs **David's critical path**._
_Run `/clapper-status` for a live re-check; run `/clapper-ship` to execute the automatable path._

App: **The Clapper - Gesture Remote** · Bundle `com.edgeless.theclapper` · ASC app id `6771928524` · Team `9BKHLSZVGF` · Tier **Free**

---

## ✅ Already done (verified, no action needed)

- **Apple Developer account** active (`thedavidmurray@gmail.com`, team 9BKHLSZVGF)
- **Distribution certificate** present ("Apple Distribution: Edgeless Technologies")
- **Bundle ID** registered (`DM3S4N66C9`)
- **ASC app record EXISTS** (`6771928524`) ← the one step Apple's API can't do; it's done.
- **Distribution provisioning profile** exists in repo (`fastlane/profiles/TheClapper_AppStore.mobileprovision`)
- **ASC API key** present (`AuthKey_N4R7KBVD5A.p8`) → fastlane runs headless
- **App code** feature-complete; **simulator build** succeeds

> Your earlier worry about "certificate blockers I'm the critical path on" is largely resolved — the cert, profile, bundle, and app record all already exist.

---

## 🤖 Automated by `/clapper-ship` (no David action)

| Step | Lane / action |
|------|---------------|
| Install dist profile locally | copy `.mobileprovision` → `~/Library/MobileDevice/Provisioning Profiles/` |
| Capture 6.9" screenshots (1320×2868) | `clapper-assets` workflow (simulator capture) |
| Real-footage app preview | `clapper-assets` workflow (`simctl io recordVideo`) |
| Generate `deliver` metadata tree | `clapper-assets` workflow from `AppStoreMetadata.md` |
| Bump build number + signed IPA + TestFlight | `fastlane ios beta` |
| Push listing (metadata + screenshots), **no submit** | `fastlane deliver --skip_submission` |

---

## 🙋 David's critical path (human-gated — only you can do these)

These require the **App Store Connect web UI** or your decision; the API/automation cannot.

### 1. Confirm the **Free Apps agreement** is active  _(2 min — likely already done)_
- URL: <https://appstoreconnect.apple.com/agreements>
- Under **Agreements, Tax, and Banking**, the **Free Apps** agreement must show **Active**. If it shows "Review/Accept," click through it. (Free tier = no bank/tax needed.)
- _Why human-gated:_ Apple blocks the API until the current license agreement is accepted under your Account Holder login.

### 2. Answer the **App Privacy** questionnaire  _(5 min — required, web-only)_
- URL: <https://appstoreconnect.apple.com/apps/6771928524/distribution/privacy>
- The Clapper: **mic + camera used on-device, nothing collected/transmitted.** Answer **"Data Not Collected"** (matches `AppStoreMetadata.md` Privacy section). 
- _Why human-gated:_ Apple does not expose the privacy questionnaire over the API.

### 3. Set **age rating** + **export compliance**  _(2 min)_
- Age rating: **4+** (no objectionable content).
- Export compliance: app uses only standard encryption → answer **"No"** to "uses non-exempt encryption" (Info.plist should declare `ITSAppUsesNonExemptEncryption = false` so this is auto-answered; verify in the build's listing).

### 4. Review the staged listing, then approve submission  _(5 min)_
- After `/clapper-ship` stages everything, open the app in ASC, eyeball the screenshots/description/preview.
- When you're happy, tell me **"submit"** in-session and I run `fastlane ios release`. **I will never submit without your explicit yes.**

### If 2FA prompts during any fastlane upload
- The API key avoids most 2FA, but if an interactive Apple login appears, approve the push on your trusted device and re-run the lane.

---

## Blocker protocol
If an automated step stalls >10 min on an Apple bureaucracy step (agreement sync, profile sync, 2FA loop): document the exact error, fall back to the manual URL above, mark the deliverable human-gated here, and continue the next independent step. Don't fight Xcode signing for 30 min when a 2-min portal click is the standard fix.
