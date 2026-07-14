# Two of Us

Native iOS baby tracking app for Taylor and his wife to track their newborn son Miller.  
Distributed via TestFlight to 2 users (both parents).

## Status: In active development — Phase 1 (core logging) implemented in SwiftUI + SwiftData. CloudKit sync, widgets, Live Activities, and Siri intents in progress.

## Tech Stack
- **SwiftUI** — declarative UI, iOS 17+
- **SwiftData** — local persistence, the on-device source of truth
- **CloudKit** — real-time sync between both parents' iPhones, free for 2 users, no server. Hand-rolled on `CKSyncEngine` + a zone-wide `CKShare` (TwoOfUs/Sync/), NOT SwiftData's automatic mirroring — the shared-database sharing model is impossible through it
- **WidgetKit** — lock screen and home screen widgets ("time since last feed")
- **ActivityKit / Live Activities** — real-time timer on lock screen and Dynamic Island during feeds/sleep
- **App Intents / Siri** — "Hey Siri, log a diaper change"
- **Swift Charts** — built-in iOS charting for sleep/feed patterns

## Key requirements
- Native iOS app (SwiftUI), not a web app — decision locked in docs/IOS_VS_WEB_COMPARISON.md
- Two users (both parents) tracking the same baby
- Real-time sync via CloudKit — both see updates within ~10 seconds
- Quick logging — as few taps as possible (you're holding a baby)
- Clean, calming design (not clinical)
- Dark mode from day 1
- Distributed via TestFlight today; a first **App Store** release is now in
  preparation (privacy manifest, nutrition label, screenshots, age rating, a
  second Xcode Cloud archive workflow) — see `docs/APP_STORE_RELEASE_RUNBOOK.md`
  and `docs/RELEASE_POLISH_PLAN.md` §18
- CI/CD via Xcode Cloud, two workflows (see docs/XCODE_CLOUD.md):
  - **"Default"** — pushes to `main` archive and upload to TestFlight (internal-only builds; these can NEVER be submitted to the App Store)
  - **"App Store Release"** — tags matching `v*` (e.g. `git tag v1.0.1 && git push origin v1.0.1`) archive with App Store Connect distribution; only these builds can be attached to an App Store version. Tag the exact commit already proven on TestFlight, and make sure `MARKETING_VERSION` in project.yml matches the tag.
  - `ci_scripts/ci_post_clone.sh` regenerates the gitignored .xcodeproj on the runner for both
- Unit tests — `make test` runs TwoOfUsTests (CloudKit record mapping round-trips, sync hold-queues, store semantics) on the simulator; no iCloud account needed
- TestFlight feedback automation — hourly GitHub Action polls App Store Connect for beta feedback/crashes and files them as issues labeled `testflight-feedback` (see docs/TESTFLIGHT_AUTOMATION.md)
