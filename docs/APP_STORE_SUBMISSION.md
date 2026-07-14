# App Store Submission — v1.0 Final Checklist

Status as of **2026-07-14, 11:15 AM** (updated after the browser session in
App Store Connect). Everything below is ✅ done except the last two clicks.

---

## ✅ Completed — repo side

- `main` builds clean (verified 2026-07-14, zero errors); all branches merged.
- `MARKETING_VERSION` is `1.0`; build numbers stamped from `CI_BUILD_NUMBER`.
- Export compliance pre-answered: `ITSAppUsesNonExemptEncryption: NO` in the
  Info.plist — ASC never asks the encryption question.
- Screenshots captured 2026-07-14 from current `main` (seeded "Charlie" data,
  clean 9:41 status bar), light + dark, committed under `screenshots/`:
  6.9" (1320×2868), 6.5" (1242×2688), iPad 13" (2064×2752).
  Regenerate any time: `scripts/capture_appstore_screenshots.sh`.

## ✅ Completed — App Store Connect (done in the 2026-07-14 session)

**Version page (1.0):**
- Name, promo text, description, keywords, support URL, copyright, contact
  info, review notes — all filled (done previously by Taylor).
- **Screenshots uploaded**: 10 iPhone 6.5" (5 light then 5 dark, in order) and
  10 iPad 13" — verified "10 of 10" in both slots.
- **Sign-in required unchecked** (app needs no account for review).
- App Privacy: published, "Data Not Collected". Auto-release on approval: on.

**App Information:**
- Subtitle set: "Baby tracking for two parents".
- Category: **Health & Fitness** primary, **Lifestyle** secondary.
- Content rights: declared no third-party content.
- **Age rating questionnaire completed → 4+** (172 countries; AL Brazil,
  ALL Korea, 00+ Vietnam). Age category: Not Applicable (not Made for Kids).
- **Regulated medical device: declared NO** (required because the app is in
  Health & Fitness).

**Account / compliance:**
- **EU DSA trader status: declared non-trader** — "You have completed all
  regulatory requirements at this time." Compliance shows Active (Jul 14, 2026).
  The submission-blocking banner is gone.

**Xcode Cloud:**
- Root cause found for build attachment: every existing build (56–66) was
  **INTERNAL_ONLY** — the "Default" workflow archives for TestFlight internal
  testing only, which ASC refuses to attach to an App Store version (the Add
  Build radios were all disabled; confirmed via `buildAudienceType`).
- Fix (runbook owner-task C4, done 2026-07-14 with Taylor's approval):
  duplicated the workflow → **"App Store Release"** — distribution
  **App Store Connect** (TestFlight and App Store), start condition
  **Manual Start** only, Xcode "Latest Release" (26.5). Original "Default"
  workflow untouched.
- **Build 67** ran on the new workflow (uploaded 9:09 AM PT, processed
  `APP_STORE_ELIGIBLE`) and is **attached to version 1.0 and saved**.
  (Builds 68+ from the "Default" workflow remain INTERNAL_ONLY — ignore them;
  future App Store builds must come from the "App Store Release" workflow.)
- "Sign-in required" unchecked and saved (no account needed for review).

---

## 🖐️ What's left for Taylor (one click)

Open the 1.0 version page → **Add for Review** → confirm →
**Submit to App Review**. Auto-release is on, so approval = live.

## Known v1 limitations (documented, not blockers)

- Formula-only feeding (no nursing/pumping) — deliberate v1 scope.
- Widget + Live Activity shots not in the listing (need a physical device);
  add in 1.0.1 (`docs/appstore/SCREENSHOT_SHOTLIST.md` has the plan).
- CloudKit sharing requires both parents on iOS 17+ with iCloud signed in;
  risk register and schema-change rules in `docs/CLOUDKIT_RISKS.md`.
- Production CloudKit schema must stay additive-only.
- App Review may test without an iCloud account: the app runs local-only and
  degrades gracefully (covered in review notes).

## If App Review rejects — prepared answers

- **"Why iCloud?"** → sync between two parents; works without it (review notes).
- **Privacy label vs. iCloud data** → "Data Not Collected" is correct: data
  lives in the user's own iCloud database; the developer runs no server and
  can access nothing (`docs/APP_PRIVACY_ANSWERS.md`).
- **Kids-category confusion** → the app is *for parents*, not directed at
  children (`docs/PRIVACY.md`).
- **Health & Fitness scrutiny** → the app records observations only; no
  diagnosis/treatment advice; declared not a regulated medical device.
