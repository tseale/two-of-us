# App Store Release Runbook

The path from the current TestFlight train to a public **App Store** release.
Most of this is App Store Connect / Developer-portal work that lives outside the
repo — this runbook is the checklist and the source of truth for "what's left."

> Goal change: the project originally targeted **TestFlight only**. The first
> public release adds submission-only requirements TestFlight never enforced.
> See `RELEASE_POLISH_PLAN.md` §18.

## 0. Pre-flight (in-repo — mostly done)
- [x] Privacy manifest committed (`TwoOfUs/PrivacyInfo.xcprivacy`).
- [ ] Bump `MARKETING_VERSION` in `project.yml` for the public 1.0 (confirm it
      sorts ahead of the TestFlight train already uploaded).
- [ ] Confirm `aps-environment` archives as `production` for the App Store
      configuration (it's `development` in `project.yml`; Xcode/Cloud flips it
      for a Release/App Store archive — verify in the built `.ipa` entitlements).

## 1. App Store Connect — app record
- [ ] Create / confirm the app record matches bundle id `com.taylorseale.twoofus`.
- [ ] **Privacy nutrition label**: map from `docs/PRIVACY.md` — user-provided
      baby/event data, stored in the user's own iCloud, **no tracking**, **no
      third-party sharing**, no data collected by the developer.
- [ ] **Age rating** questionnaire.
- [ ] **Category** (e.g. Health & Fitness or Lifestyle), subtitle, keywords.
- [ ] **Support URL** + marketing URL.
- [ ] Children's-privacy review (the app records a *parent's* data about their
      child; it is not directed at children — re-confirm per `PRIVACY.md`).

## 2. Listing assets
- [ ] Screenshots: iPhone (6.9"/6.5") and iPad, **light + dark**. Automated:
      `scripts/capture_appstore_screenshots.sh` → `docs/appstore/screenshots/`
      (shots 1–5); widget/Live Activity shots remain manual — see
      `docs/appstore/SCREENSHOT_SHOTLIST.md`.
- [x] Description + promotional text — drafted in
      `docs/appstore/LISTING_COPY.md`. Two open picks: promo-text variant
      (named vs generic) and the app-name fallback if "Two of Us" is taken.
- [x] Privacy policy page — publish-ready at
      `docs/appstore/PRIVACY_POLICY.md`; needs a public URL (GitHub Pages or
      similar), then paste into ASC (Privacy Policy URL + Support URL).
- [ ] App icon: finish the Liquid Glass icon in Icon Composer (macOS) — see
      `docs/ICON_AND_SPLASH_MAC_STEPS.md`. PNG fallback is an acceptable backstop.

## 3. CI / archive
- [ ] Add a **second Xcode Cloud workflow** that archives for **App Store**
      distribution. Configure it in App Store Connect → Xcode Cloud. **Do not
      modify** the existing TestFlight workflow. `ci_scripts/ci_post_clone.sh`
      regenerates the project on the runner for both.

## 4. Capabilities / portal
- [ ] iCloud container capability enabled on the bundle id; CloudKit schema
      deployed to **Production** (`docs/CLOUDKIT_SETUP.md`).
- [ ] Push (silent) enabled; APNs production environment.

## 5. QA gate (must pass on hardware — see the other runbooks)
- [ ] `docs/TESTFLIGHT_MANUAL_CHECKLIST.md` complete.
- [ ] `docs/DEVICE_TEST_MATRIX.md` covered.
- [ ] `docs/ACCESSIBILITY_CHECKLIST.md` passed.

## 6. Submit
- [ ] Upload the App Store archive, attach screenshots/metadata, submit for
      review. Export-compliance is pre-answered via `ITSAppUsesNonExemptEncryption=NO`.
