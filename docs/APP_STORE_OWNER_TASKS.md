# App Store release — Taylor's checklist

Everything left that only you can do (Apple sign-ins, account-level decisions,
hardware). Each item says what it unlocks, so after you do it Claude can take
the next stretch alone. Ordered by impact; timings are realistic.

The in-repo work is **done**: sync hardening merged, screenshots captured,
listing copy + nutrition-label answers + privacy policy drafted, runbook
current. See `APP_STORE_RELEASE_RUNBOOK.md` for the master list.

---

## A. Text-message decisions (2 minutes, from anywhere)

Reply to Claude with answers to any of these whenever — no computer needed:

1. **Promo text** — name Miller in the public listing, or generic?
   (Both versions ready in `docs/appstore/LISTING_COPY.md`.)
2. **App name fallback** if "Two of Us" is taken on the App Store:
   `Two of Us — Baby Tracker` / `Two of Us: Baby Log` / `Two of Us Baby`.
3. **Category**: Health & Fitness primary + Lifestyle secondary (recommended),
   or flip them.
4. **Privacy-policy hosting**: the repo is private (free plan), so GitHub
   Pages isn't available here. Say the word and Claude creates a tiny
   **public** repo (`twoofus-site`) with the policy + a support page and turns
   on Pages — the URL lands in ASC. (Alternative: any host you prefer.)
5. **Stale worktrees**: "delete the stale worktrees" authorizes removing the
   two June 8 pre-rename worktrees under `.claude/worktrees/` (contents
   inspected: superseded; diffs snapshotted).
6. **App icon**: "PNG fallback is fine" ships the current icon; otherwise the
   Liquid Glass icon needs you in Icon Composer
   (`docs/ICON_AND_SPLASH_MAC_STEPS.md`, ~20 min at the Mac).

## B. CloudKit Console — 30 min at a computer, HIGHEST PRIORITY

The one item that can silently break TestFlight/App Store builds. Production
schema is additive-only with no just-in-time creation; the avatar fields
(`photoData`) landed after the last known deploy.

1. Sign in at <https://icloud.developer.apple.com> → container
   `iCloud.com.taylorseale.twoofus`.
2. **Development** env → Schema → Record Types: verify all six types and every
   field against the table in `docs/CLOUDKIT_SETUP.md` (add missing fields by
   hand — `photoData` on Baby/Participant is the likely gap).
3. Schema → **Deploy Schema Changes** → review the diff → deploy to
   **Production**.

> Shortcut: do step 1 while Claude is connected and say "drive the schema
> check" — the browser clicking and field-by-field comparison is delegable
> once you're signed in.

## C. App Store Connect — ~45 min at a computer

1. **Create the app record**: <https://appstoreconnect.apple.com> → My Apps →
   ＋ → New App → iOS, name **Two of Us** (fallbacks above), language
   English (U.S.), bundle ID `com.taylorseale.twoofus`, SKU `twoofus-001`.
2. **API key for Claude** (this is the big unlock): Users and Access →
   Integrations → App Store Connect API. Check whether the existing key (the
   one the TestFlight-feedback Action uses) has the **App Manager** role — if
   not, create one with it, download the `.p8` once, and put it at
   `~/.appstoreconnect/` on the Mac mini with a note of the Key ID + Issuer ID.
   **With that key Claude can upload the description, keywords, promo text,
   screenshots, and privacy-label answers via the ASC API/fastlane — the whole
   listing — without further sign-ins.**
3. **Privacy label + age rating**: if you'd rather click through them yourself,
   every answer is pre-written in `docs/appstore/PRIVACY_NUTRITION_LABEL.md`
   (headline: "Data Not Collected", rating 4+). With the API key, Claude does it.
4. **Second Xcode Cloud workflow**: your app → Xcode Cloud → Manage Workflows →
   duplicate the TestFlight workflow → rename "App Store Release" → set the
   archive action's distribution to **TestFlight and App Store** → set start
   condition to **manual only**. (Leave the existing workflow untouched.)

## D. Hardware — during the bake week, phones in hand

1. Both phones install the new TestFlight build (has the sync-hardening
   fixes). Live with it a few days; watch for anything filed by the feedback
   automation.
2. Run `docs/TESTFLIGHT_MANUAL_CHECKLIST.md`, `docs/DEVICE_TEST_MATRIX.md`,
   and `docs/ACCESSIBILITY_CHECKLIST.md` against it.
3. Two shots Claude can't automate: a Lock-Screen/Home-Screen **widget**
   screenshot and a **Live Activity** (Dynamic Island) screenshot from a real
   device — see the widget section of `docs/appstore/SCREENSHOT_SHOTLIST.md`.

## E. What Claude does once the above land

- A4/decision → publish the privacy policy + support page, paste-ready URLs.
- C2 → upload all metadata, screenshots, privacy label, age rating via the API;
  prepare the 1.0 version in ASC for your final review.
- B → nothing further; that fully de-risks CloudKit.
- C4 + D → when the bake week is clean: start the App Store workflow, attach
  the build, pre-fill App Review notes (drafted in the nutrition-label doc),
  and hand you the Submit button.

**The only two clicks Claude will never take without you: submitting for App
Review, and anything that charges/agrees on your Apple account.**
