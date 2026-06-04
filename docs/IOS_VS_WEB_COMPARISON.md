# Native iOS vs Progressive Web App: Miller Time Build Decision

**Decision:** Build **native iOS with SwiftUI + CloudKit**

This document compares building Miller Time as a native iOS app (TestFlight distribution) vs a Progressive Web App across 15 critical dimensions. Each comparison is honest about tradeoffs—no dimension is universally "better," but the sum favors native iOS for this use case.

---

## Dimension Comparison

### 1. Development Speed
**Initial PWA advantage; native catches up quickly**

- **PWA:** TypeScript + React + service workers is familiar to most web devs. Framework maturity means scaffolding is fast. ~1–2 weeks to MVP with offline sync.
- **Native:** SwiftUI learning curve exists, but Claude Code closes it significantly. Syntax is simpler than you'd expect. ~3–4 weeks to MVP. **Gap is 1–2 weeks, not months.**
- **Verdict:** PWA edges out by 1–2 weeks initially, but native catches up if you're willing to learn. The gap shrinks on iteration 2+.

**Recommendation:** If speed-to-launch is your only metric, PWA wins slightly. If you care about long-term velocity and user experience, native pays for itself in weeks.

---

### 2. User Experience
**Native wins decisively**

- **PWA:** Browser constraints limit what you can do. Scrolling can feel sluggish on older iPhones. CSS animations max out at ~60fps but often hit jank. Bottom sheet dismissal is janky without custom tricks.
- **Native:** SwiftUI animates at 120fps (on Pro models) effortlessly. Haptic feedback is free—tapping a button gives tactile confirmation. Spacing, fonts, and spacing adapt automatically to iOS conventions. Users feel *right*.
- **Verdict:** Native UX is indisputably better. When you're logging a feed at 3 AM, smooth animations and haptics matter.

---

### 3. Push Notifications
**Native is bulletproof; PWA is unreliable on iOS**

- **PWA:** Service Worker push works on Chrome/Android. On iOS Safari, push notifications are **explicitly not supported by Apple**. Users must have the app open to get real-time updates. Workarounds exist (polling every 30s) but drain battery.
- **Native:** Apple Push Notification service (APNs) is battle-tested. When one parent logs a feed, the other parent's phone vibrates instantly, even if they're in another app. Delivery is ~99.9%.
- **Verdict:** If real-time sync between two parents is important (and it is), PWA doesn't have a viable answer on iOS.

---

### 4. Offline Support
**Native is solid; PWA is fragile**

- **PWA:** Service Worker + IndexedDB works on modern browsers, but iOS Safari has severe cache quota limits (~50 MB shared across all apps). Cache invalidation is a minefield (stale assets, race conditions). Many teams have been burned by broken offline sync when they least need it.
- **Native:** SwiftData (or CoreData) is battle-tested since 2009. Local storage is reliable, conflicts sync cleanly to CloudKit, and you never get trapped in sync hell.
- **Verdict:** Both work offline, but native's sync is trustworthy. PWA requires obsessive testing and still has edge cases.

---

### 5. Background Timers
**CRITICAL DECISION POINT — Native wins decisively**

- **PWA:** When you switch to another app or lock your phone, JavaScript stops running. Timers die. You can't show a live "30 mins since last feed" counter on the lock screen. Workarounds exist (push notifications every minute) but are crude and battery-intensive.
- **Native:** 
  - **Live Activities (iOS 16+):** A widget on the lock screen and Dynamic Island showing live elapsed time—updates every second without waking the phone. Parent can glance at their phone to see "31 mins since last feed" without unlocking it.
  - **Background timers:** App can keep a low-power timer running in the background to track time, trigger alerts, etc.
- **Verdict:** If you want a "time since last event" display on the lock screen (and you should—it's incredibly useful for a tired parent), PWA simply cannot do it. This is reason #1 to go native.

---

### 6. Real-Time Sync
**CloudKit is free and simple; WebSocket requires a server**

- **PWA:** You need a backend server (Node.js, Python, Go) running WebSockets or polling. Even a simple CRUD app needs ops and monitoring. Costs ~$10–50/month on Heroku/Railway. Deployment and database management add complexity.
- **Native:** CloudKit is Apple's iCloud-based database. It's designed for 2–10 users (perfect for a couple and their baby). Sync is automatic. Conflicts resolve with last-write-wins or custom logic. Free tier covers light use. No server to maintain.
- **Verdict:** CloudKit eliminates an entire class of complexity. For a 2-user app, it's unbeatable.

---

### 7. Distribution & Installation
**Native is cleaner**

- **PWA:** "Add to Home Screen" requires the user to tap Share > Add to Home Screen > Add. Most users don't know this. No icon in the App Store. Feels hacky.
- **Native:** TestFlight link via email. User taps link, hits "Install," and the app appears on their home screen indistinguishable from App Store apps. Feels professional and polished.
- **Verdict:** Native distribution is simpler and more discoverable.

---

### 8. Home Screen Presence
**Native looks native; PWA looks like a web page**

- **PWA:** Home screen icons often include Safari chrome or browser artifacts. Splash screens are sometimes janky. It feels like a shortcut to a web page (because it is).
- **Native:** Icon on the home screen looks exactly like an App Store app. Splash screen is perfect because it's built into the app. Taps feel instantaneous.
- **Verdict:** Native feels like a real app. PWA feels like a bookmark, even if it's technically an app.

---

### 9. Maintenance & Auto-Updates
**Both work; native is slightly cleaner**

- **PWA:** Service Worker caching means updates can be delayed or stale. You control when the new code is downloaded, but users can end up on old versions. Cache invalidation requires careful versioning.
- **Native:** TestFlight auto-updates every 30 days (or you can force immediate updates). App Store would auto-update silently. No cache confusion.
- **Verdict:** Native is cleaner. PWA requires more care to avoid stale code.

---

### 10. Cost
**Native is $99/yr; PWA is "free" (but requires a server)**

- **PWA:** No Apple dev account needed. But you need a backend server, domain, SSL cert, monitoring. Real cost: ~$10–50/month (~$150–600/yr).
- **Native:** Apple Developer Program is $99/yr. CloudKit is free. No other costs.
- **Verdict:** Native is cheaper overall. PWA's apparent "free" cost is misleading.

---

### 11. Widgets (Lock Screen & Home Screen)
**Native only**

- **PWA:** Cannot show widgets on lock screen or home screen. Zero chance of adding this.
- **Native:** WidgetKit can show:
  - Lock screen widget: "34 mins since last feed" (updates live)
  - Home screen widget: Last 5 events, quick "log feed" button
  - Dynamic Island: Baby's name, time since last event
- **Verdict:** Widgets are huge UX wins for a baby-tracking app. PWA can't compete.

---

### 12. Apple Watch
**Native can extend; PWA cannot**

- **PWA:** No watch support. Period.
- **Native:** WatchKit can add a watch app for quick logging: "Hey, I changed a diaper" taps the watch and syncs to iPhone. Quick without unlocking phone.
- **Verdict:** Watch support is a future feature, but it's only possible with native. Nice to have for later.

---

### 13. Siri Integration
**Native can use App Intents; PWA cannot**

- **PWA:** No Siri support.
- **Native:** App Intents framework allows Siri shortcuts: "Hey Siri, log a diaper change" or "Hey Siri, when was the last feed?" Incredibly useful when holding a baby.
- **Verdict:** Siri integration is a low-effort future feature with high convenience for the use case.

---

### 14. Dark Mode
**Both handle it; native is effortless**

- **PWA:** CSS media queries for dark mode work fine. @media (prefers-color-scheme: dark). Requires manual implementation.
- **Native:** SwiftUI respects system dark mode automatically. One @Environment variable and you're done.
- **Verdict:** Both are feasible. Native is slightly simpler.

---

### 15. Camera
**Native is full-featured; PWA is limited on iOS**

- **PWA:** `<input type="file">` for photos. On iOS Safari, you can take a photo or choose from Photos, but browser permissions are limited. Some apps have had issues with privacy.
- **Native:** Full access to camera, Photo Library, Live Photo capture. Easier to ask for permission and explain why. Can build custom camera UI if needed.
- **Verdict:** If you ever want to store photos (e.g., milestone pictures), native is safer. PWA works but is less flexible.

---

## Summary Table

| Dimension | PWA | Native | Winner |
|-----------|-----|--------|--------|
| **Dev speed** | 1–2 weeks | 3–4 weeks | PWA (+1–2 weeks) |
| **UX polish** | Good (60fps, limited haptics) | Excellent (120fps, haptics, natural) | **Native** |
| **Push notifications** | ❌ Not on iOS Safari | ✅ APNs bulletproof | **Native** |
| **Offline** | Works (fragile) | Works (reliable) | **Native** |
| **Background timers** | ❌ No live lock screen | ✅ Live Activities + widgets | **Native** |
| **Real-time sync** | Need server (~$150–600/yr) | CloudKit free | **Native** |
| **Distribution** | "Add to Home Screen" | TestFlight link | **Native** |
| **Home screen feel** | Feels like a bookmark | Feels like an app | **Native** |
| **Maintenance** | Cache invalidation tricky | Auto-updates clean | **Native** |
| **Cost** | ~$150–600/yr (server) | $99/yr (dev account) | **Native** |
| **Widgets** | ❌ Not possible | ✅ Lock screen + home screen | **Native** |
| **Apple Watch** | ❌ Not possible | ✅ WatchKit support | **Native** |
| **Siri** | ❌ Not possible | ✅ App Intents | **Native** |
| **Dark mode** | Works (manual) | Works (automatic) | **Native** |
| **Camera** | Limited | Full | **Native** |

---

## Recommendation: Build Native iOS with SwiftUI + CloudKit

### Why Native Wins

1. **Live lock screen timer:** Background timers + Live Activities let parents see "34 mins since last feed" on the lock screen. This is impossible with PWA and is a killer feature for a sleep-deprived parent.

2. **Push notifications work:** APNs is reliable. When Taylor logs a feed, his wife's phone vibrates instantly, even if she's in another app. PWA has no answer for this on iOS.

3. **CloudKit is free and simple:** No server to maintain, no database to manage. CloudKit handles sync for 2–10 users beautifully.

4. **Better UX:** Haptics, smooth animations, native controls. It will feel like a real app, not a web page.

5. **Future-proofing:** Widgets, watch, Siri—all become possible later. PWA is a dead-end for these features.

6. **Cost is lower:** $99/yr for dev account. PWA needs a $150–600/yr server.

7. **TestFlight distribution is painless:** Send a link, they install. No "Add to Home Screen" confusion.

### Tradeoff: 2-Week Development Delay

The only real cost is 1–2 weeks slower initial launch (3–4 weeks for native vs 1–2 weeks for PWA). **But** iterating on a PWA would be slower because you'd hit these pain points one by one (no push notifications, server costs, cache bugs). Native gets those for free.

### Next Steps

1. **Update BUILD_PLAN.md:** Reflect the native iOS decision. Timeline: 3–4 weeks to MVP with SwiftUI + CloudKit.
2. **Learn SwiftUI:** Claude Code can help significantly. Start with Apple's 100 Days of SwiftUI tutorials in parallel.
3. **Sketch the CloudKit schema:** Simple entities: Baby (name, birth date), Event (type, timestamp, synced to both parents).
4. **EnrollApple Developer Program:** $99/yr. Required for TestFlight.

---

## Dissent & Counter-Arguments

### "I want to ship in 2 weeks, not 3–4"
**Valid.** If you ship PWA in 2 weeks and then switch to native in week 4, you've learned a lot. PWA can be a prototype. But be aware: migrating user data from PWA to native is work, and you'll likely rebuild anyway.

### "I don't want to learn SwiftUI"
**Fair.** SwiftUI has a learning curve. But Claude Code makes it manageable. You'll hit some head-scratchers (State management, property wrappers), but tutorials + Claude will unblock you quickly. If you're allergic to learning a new language, PWA is the right choice.

### "My wife won't install TestFlight"
**Unlikely.** TestFlight is designed for exactly this: letting non-developers install beta apps. Link in email, one tap. If she can install an App Store app, she can install TestFlight.

### "CloudKit is Apple-only"
**True.** If Taylor ever gets an Android phone, a CloudKit-only app breaks. But Miller Time is designed for two people: Taylor and his wife. Both on iOS? Go native. One on Android? Reconsider PWA or use a cross-platform backend (Firebase, Supabase).

---

## Decision Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-06-04 | **Native iOS (SwiftUI + CloudKit)** | Live lock screen timers + reliable push + free sync > 2-week dev delay |

