# App Store Submission — v1.0 Final Checklist

Status as of **2026-07-14**. This is the last-mile document: everything below
is either ✅ done, or a short manual step only Taylor can click in App Store
Connect. When the manual steps are done, hit **Add for Review**.

---

## ✅ Completed

### App Store Connect (version page)
- App name: **The Two of Us**
- Promotional text, description (2,289 chars), keywords — filled
- Support URL: <https://tseale.github.io/two-of-us/>
- Privacy Policy URL: <https://tseale.github.io/two-of-us/#privacy>
- Copyright: 2026 Taylor Seale
- Contact info + review notes — filled
- App Privacy: **published — "Data Not Collected"**
- Auto-release on approval: **enabled**

### Build
- `main` builds clean (verified 2026-07-14, `xcodebuild` generic/iOS, zero errors).
- All feature branches are merged; the only outstanding branch content was the
  CloudKit risk-assessment doc, now merged to `main`.
- Xcode Cloud archived the latest `main` merge **today, 2026-07-14 14:36 UTC**
  (commit `0185ad0`, "TwoOfUs | Default | Archive - iOS" → success, 0 errors /
  2 warnings). Build numbers are stamped from `CI_BUILD_NUMBER`
  (`ci_scripts/ci_post_clone.sh`), so this upload supersedes build 63.
- `MARKETING_VERSION` is `1.0` — matches the ASC version.
- `aps-environment` is `development` in `project.yml` by design; distribution
  signing flips it to `production` (already proven by push-driven sync working
  on existing TestFlight builds).
- Export compliance is pre-answered: `ITSAppUsesNonExemptEncryption: NO` is in
  the Info.plist (standard HTTPS/CloudKit crypto only), so ASC will not ask
  the encryption question when the build is attached.

### Screenshots (this repo, `screenshots/`)
Captured 2026-07-14 from current `main` with seeded sample data ("Charlie",
clean 9:41 status bar), light **and** dark, via
`scripts/capture_appstore_screenshots.sh screenshots`:

| Set | Size | Path | Use in ASC |
|---|---|---|---|
| iPhone 6.9" | 1320 × 2868 | `screenshots/appstore-6.9/{light,dark}/` | "iPhone 6.9" Display" (primary; ASC scales down for smaller iPhones) |
| iPhone 6.5" | 1242 × 2688 | `screenshots/appstore-6.5/{light,dark}/` | "iPhone 6.5" Display" (optional fallback; scaled from the 6.9" set) |
| iPad 13" | 2064 × 2752 | `screenshots/appstore-ipad-13/{light,dark}/` | "iPad 13" Display" — **required** because the app runs on iPad |

Five shots per set, in listing order: `01-home`, `02-log-sheet`, `03-history`,
`04-stats`, `05-settings`. Suggested upload order: lead with 2–3 light shots
(home, log sheet, history), then 2 dark shots (stats, home) to sell dark mode.
Up to 10 per size are allowed. Re-generate any time with the script above.

---

## 🖐️ Manual steps for Taylor (App Store Connect)

Estimated total: **15–20 minutes**. I could not verify ASC state directly
(no active browser session and no local API key), so items 1–3 are
verify-then-fix.

1. **App Information page** (left sidebar → General → App Information):
   - **Primary category**: set to **Health & Fitness**; secondary **Lifestyle**
     (the recommendation from `docs/APP_STORE_OWNER_TASKS.md` — flip if you
     prefer).
   - **Age rating**: run the questionnaire if not done — answer "None" to every
     content question → **4+**. All answers pre-written in
     `docs/appstore/PRIVACY_NUTRITION_LABEL.md`.

2. **EU Digital Services Act banner**: Apple requires a **trader status
   declaration from every developer**, even with no EU distribution — apps
   without one are removed from the EU storefront, and the banner blocks some
   accounts from submitting. As a hobbyist distributing a free family app with
   no commercial intent, declare **non-trader** (Business → Digital Services
   Act, or follow the banner link). Non-traders provide no extra info; the app
   simply shows an EU notice that consumer-protection laws don't apply. If you
   ever monetize, revisit (traders must verify address/phone/email for display
   on the EU storefront).

3. **Verify the build**: TestFlight tab → iOS builds. Today's Xcode Cloud
   archive (from the `main` merge at ~09:36 CDT) should be the newest build —
   wait for "Processing" to clear if needed. If it stalled, check Xcode Cloud
   in ASC; build 63 also works if it hasn't expired (builds expire 90 days
   after upload).

4. **Upload screenshots**: version page → App Previews and Screenshots →
   drag the files from `screenshots/appstore-6.9/` (and the iPad set) per the
   table above.

5. **Select the build** on the version page (＋ next to Build → pick the
   newest).

6. Click **Add for Review** → **Submit to App Review**. Auto-release is
   already enabled, so approval = live.

---

## Known v1 limitations (documented, not blockers)

- **Formula-only** feeding (no nursing/pumping) — deliberate v1 scope.
- Widget + Live Activity App Store shots not included (need a physical
  device); the 5 core shots stand alone fine, add device shots in 1.0.1.
- CloudKit sharing requires both parents on iOS 17+ with iCloud signed in;
  the join flow depends on the zone-wide `CKShare` (see
  `docs/CLOUDKIT_RISKS.md` for the full risk register and schema-change rules).
- Production CloudKit schema must stay additive-only — never rename/delete
  deployed record fields (`docs/CLOUDKIT_RISKS.md`).
- App Review may test without an iCloud account: the app works local-only and
  degrades gracefully (review notes in ASC already cover this).

## If App Review rejects

Most likely asks, and the prepared answers:
- **"Why does it need iCloud?"** → sync between two parents; works without it.
  Covered in review notes.
- **Privacy label vs. iCloud data** → "Data Not Collected" is correct: data
  lives in the *user's own* iCloud database; the developer operates no server
  and can access nothing. `docs/APP_PRIVACY_ANSWERS.md` has the full rationale.
- **Kids category confusion** → the app is *for parents*, not directed at
  children (`docs/PRIVACY.md`).
