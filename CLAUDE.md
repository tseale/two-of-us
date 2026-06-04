# Miller Time

Native iOS baby tracking app for Taylor and his wife to track their newborn son Miller.  
Distributed via TestFlight to 2 users (both parents).

## Status: Research & design phase — no code yet.

## Tech Stack
- **SwiftUI** — declarative UI, iOS 17+
- **SwiftData** — local persistence, automatic CloudKit sync
- **CloudKit** — real-time sync between both parents' iPhones, free for 2 users, no server
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
- TestFlight distribution — no App Store submission needed
