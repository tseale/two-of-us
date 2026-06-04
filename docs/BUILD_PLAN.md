# Miller Time — Build Plan

**Baby**: Miller  
**Users**: Taylor + wife  
**Goal**: Track feeds, sleep, and diapers in real-time across both parents' phones  
**Last Updated**: June 2026

---

## Recommended Tech Stack

### Backend: FastAPI (Python)
**Why**: Taylor already runs Word Feeder and Sleeper Cell on FastAPI on his Mac mini — same tooling, same hosting, zero new infrastructure. FastAPI has native WebSocket support for real-time sync, which eliminates the need for Firebase or a separate pub/sub service.

### Database: SQLite (MVP) → PostgreSQL (if needed)
**Why**: Two users, one baby, maybe 50 events/day. SQLite handles this with room to spare and requires zero server setup. A single `.db` file is trivially backed up. Upgrade path to PostgreSQL is straightforward via SQLAlchemy if query complexity grows.

### Frontend: React + TypeScript + Vite
**Why**: React's ecosystem (Zustand, React Query, Framer Motion) maps exactly to the needs here. Vite's PWA plugin handles service worker generation and offline caching with minimal configuration. TypeScript catches event shape mismatches early — critical when feeding/sleep/diaper all share a timeline model.

### Real-Time Sync: FastAPI WebSockets
**Why**: No external service needed. FastAPI's WebSocket support is production-ready. A single broadcast room per baby — when parent A logs an event, the server broadcasts to parent B's open connection. Latency target: <200ms on same network, <500ms over mobile. Fallback to 10s polling if WebSocket drops.

### Styling: Tailwind CSS + shadcn/ui
**Why**: Tailwind's utility classes make mobile-first layouts fast to build. shadcn/ui provides accessible, unstyled components that can be themed for the calm aesthetic without fighting a component library's defaults.

### Offline: Vite PWA Plugin + idb (IndexedDB wrapper)
**Why**: Vite PWA plugin generates the service worker automatically. IndexedDB via `idb` stores events locally and queues sync. Background Sync API sends queued events when connection returns.

### Auth: JWT + shared invite code
**Why**: Two users total. No need for OAuth or a user management system. Email + password for account creation, invite-link or 6-digit code to add second parent to the same baby profile.

### Hosting: Mac mini + Tailscale (already solved)
Same pattern as Word Feeder and Sleeper Cell. FastAPI serves the built React frontend as static files + API on the same process. HTTPS via Tailscale.

---

## Data Model

```
Baby
  id, name, dob, created_at

User
  id, email, password_hash, created_at

BabyUser (join table)
  baby_id, user_id, role (owner | partner)

Event
  id, baby_id, user_id
  type: ENUM(feed, diaper, sleep)
  started_at, ended_at (nullable)
  duration_seconds (derived, stored for query speed)
  notes (nullable)
  created_at, updated_at, deleted_at (soft delete)

FeedDetail
  event_id
  method: ENUM(breast_left, breast_right, breast_both, bottle)
  amount_ml (nullable, for bottle)

DiaperDetail
  event_id
  type: ENUM(wet, dirty, both)

SleepDetail
  event_id
  location (nullable: crib, bassinet, contact, etc.)
```

Events are immutable after creation (soft delete + re-create for edits in MVP). This keeps sync simple — no update conflicts.

---

## Phase 1: MVP Core

**Goal**: Both parents can log feeds, diapers, and sleep. App works on phone as a PWA. Real-time sync handled in Phase 2 — Phase 1 is reliable logging.

**Effort**: 6–7 focused days

### What to Build

#### 1. Project Scaffold (Day 1, ~4 hrs)
- FastAPI app with SQLite via SQLAlchemy + Alembic migrations
- React + TypeScript + Vite frontend
- Tailwind + shadcn/ui base config
- PWA manifest (name, icons, theme color, display: standalone)
- Serve React build from FastAPI with `StaticFiles`
- Dev proxy: Vite → FastAPI on port 8000
- Basic project structure:
  ```
  miller-time/
    backend/
      main.py
      models/
      routers/
      db.py
    frontend/
      src/
        pages/
        components/
        store/
        hooks/
    alembic/
  ```

#### 2. Auth (Day 1, ~3 hrs)
- `POST /auth/register` — email + password, creates user + baby profile
- `POST /auth/login` — returns JWT (30-day expiry)
- `POST /baby/invite` — generates 8-char invite code
- `POST /baby/join` — accepts invite code, adds user to baby profile
- JWT stored in `localStorage`, sent as `Authorization: Bearer`
- No refresh tokens in MVP — if it expires, re-login

#### 3. Event API (Day 2, ~5 hrs)
- `POST /events` — create event (feed, diaper, sleep start)
- `PATCH /events/{id}` — update (end a sleep/feed timer)
- `DELETE /events/{id}` — soft delete
- `GET /events/today` — all events for today, sorted by `started_at` DESC
- `GET /events/active` — any in-progress feed or sleep timer (no `ended_at`)
- All endpoints scoped to the authenticated user's baby
- Pydantic schemas for each event type with discriminated union

#### 4. Quick-Log UI — Main Screen (Day 3, ~6 hrs)
This is the most important screen. One-thumb operable.

Layout:
```
┌──────────────────────────────┐
│  Miller  ·  June 4           │
│  Last feed: 2h 13m ago  💧🍼 │
├──────────────────────────────┤
│                              │
│  ┌─────────┐  ┌─────────┐   │
│  │  Feed   │  │  Sleep  │   │
│  │   🍼    │  │   💤    │   │
│  └─────────┘  └─────────┘   │
│                              │
│       ┌─────────┐            │
│       │  Diaper │            │
│       │   💩    │            │
│       └─────────┘            │
│                              │
│  ──── Today ────             │
│  2:14p  Feed · Bottle 90ml   │
│  1:10p  Sleep · 1h 22m       │
│  11:40a Diaper · Wet         │
│  ...                         │
└──────────────────────────────┘
```

- Three large tap targets (min 80×80px): Feed, Sleep, Diaper
- "Last X ago" indicators above buttons — computed from today's events
- Bottom sheet appears on tap to collect minimal details
- Today's timeline below (last 5 events, "see all" link)
- No nav bar clutter — single-page feel

#### 5. Feed Logging Flow (Day 4, ~4 hrs)
Tap "Feed" → bottom sheet slides up:

```
[ Breast L ]  [ Breast R ]  [ Bottle ]
         [ Both Breast ]

  ── If Breast selected ──
  Timer starts immediately
  ● 4:23 and counting
  [      Stop      ]

  ── If Bottle selected ──
  [ 60 ]  [ 90 ]  [ 120 ]  [ __ml ]
  [      Log      ]
```

- Breast feed starts timer immediately on method selection (no extra tap)
- Timer shows elapsed time, updates every second
- Stop button saves the event with duration
- Bottle shows quick-select amounts (60/90/120ml) + manual entry
- "Both Breast" creates a single event with `method: breast_both`
- Timer persists if bottom sheet is closed (feed still in progress)

#### 6. Diaper Logging Flow (Day 4, ~1 hr)
Tap "Diaper" → bottom sheet:

```
  [ Wet ]   [ Dirty ]   [ Both ]
```

Three taps total: open app → Diaper → Wet. Done. No confirm needed — tap logs immediately with a success flash.

#### 7. Sleep Logging Flow (Day 4, ~2 hrs)
Tap "Sleep" → starts timer immediately (same pattern as breast feed):

```
  Sleeping
  ● 23 minutes
  [      Wake Up      ]
```

- Active sleep replaces the Sleep button with the live timer on the main screen
- "Wake Up" stops the timer and saves the event

#### 8. Active Timer State on Main Screen (Day 5, ~2 hrs)
When a feed or sleep is in progress, the main screen reflects it:

```
  ┌─────────────────────────────┐
  │  🍼 Feeding · 4:23          │
  │  [   Stop Feed   ]          │
  └─────────────────────────────┘
```

Active timer card appears above the log buttons. Big, obvious. One tap to stop.

#### 9. Today's Timeline (Day 5, ~3 hrs)
Full timeline page (reached from "see all" on main screen):
- Grouped by hour
- Each event: type icon, time, duration/details, "who logged" initial (T or W)
- Tap to expand: shows full details
- Tap-hold or swipe-left: delete option (soft delete)
- Pull-to-refresh (will become real-time in Phase 2)

#### 10. PWA Polish (Day 6, ~2 hrs)
- `manifest.webmanifest`: name, short_name, icons (192×192, 512×512), theme_color, background_color, display: standalone
- Vite PWA plugin with `generateSW` strategy
- App icon: design a simple "M" mark or clock icon
- Status bar color matches app header on iOS
- "Add to Home Screen" prompt nudge on first visit
- Splash screen via manifest

#### 11. Dark Mode (Day 6, ~3 hrs)
- System preference detection via `prefers-color-scheme`
- Manual toggle in settings (override system)
- Preference stored in `localStorage`
- Tailwind `dark:` classes throughout
- Dark palette: `#0D1117` background, `#1C2128` cards, muted grays, amber accent
- Test all screens in dark mode

#### 12. Integration + Bug Fix Day (Day 7)
- Connect all flows end-to-end
- Fix edge cases: active timer on page reload, multiple active events guard
- Test on actual phone (Safari + Chrome on iOS)
- Verify PWA install flow works
- Verify all three event types round-trip correctly

### Definition of Done — Phase 1
- [ ] Both parents can create accounts and join same baby profile
- [ ] Feed (breast L/R/both/bottle), diaper (W/D/both), sleep (start/stop) all log correctly
- [ ] Active timers persist across page navigations
- [ ] Today's timeline shows all events in order
- [ ] App installs to home screen on iPhone
- [ ] Dark mode works on all screens
- [ ] Runs on Mac mini, accessible via Tailscale

---

## Phase 2: Real-Time Sync + Offline

**Goal**: When one parent logs an event, the other parent's screen updates within 500ms without refreshing. App works without internet and syncs when connection returns.

**Effort**: 4–5 days

### What to Build

#### Real-Time Sync via WebSockets (2 days)
- FastAPI `/ws/baby/{baby_id}` WebSocket endpoint
- Connection manager: tracks active connections per baby
- On any event mutation (create/update/delete), broadcast serialized event to all other connections in the room
- Frontend: `useWebSocket` hook that manages connection lifecycle (reconnect on disconnect, exponential backoff)
- Zustand store receives broadcast events and merges into local state
- Optimistic updates: local state updates immediately on user action, WebSocket confirms/corrects

```python
# Connection lifecycle
connect → join room baby_id
event mutated → broadcast delta to room
disconnect → leave room
```

Broadcast payload:
```json
{
  "type": "event_created" | "event_updated" | "event_deleted",
  "event": { ...event object },
  "actor_user_id": "uuid"
}
```

- No full-state sync on connect — just fetch `GET /events/today` on connect, then apply deltas
- Presence indicator: "Taylor is viewing" / "Wife is logging" dot on main screen

#### Offline Support (2 days)
- Service worker (already installed via Vite PWA) caches app shell
- Outbound event creation queued in IndexedDB when offline
- `useNetworkStatus` hook: detects online/offline
- Offline banner: "You're offline — events will sync when connected"
- Background Sync API: fires queued POST requests on reconnect
- Conflict resolution: last-write-wins on `started_at` (for same-second conflicts, use `created_at` tiebreak)
- Sync indicator: small badge on timeline when events are pending sync

#### Edit/Delete Past Entries (0.5 day)
- Swipe left on timeline entry reveals Delete
- Tap event → edit sheet (can change type details, notes, times)
- Edits broadcast to partner via WebSocket
- Soft delete (set `deleted_at`) — never hard delete in MVP

#### Push Notifications (0.5 day, optional)
- `POST /notifications/subscribe` — stores Web Push subscription
- Server sends push via `web-push` library:
  - "Last feed was 3 hours ago" (configurable interval, default 3h)
  - "Miller has been asleep for 2 hours" (optional wake check)
- Opt-in only, per-user settings
- Notification tap opens app to today's view

### Definition of Done — Phase 2
- [ ] Parent B's screen updates within 500ms of Parent A logging
- [ ] App works completely offline — events queue and sync on reconnect
- [ ] No data loss on reconnect after being offline
- [ ] Edit and delete work and sync to other parent
- [ ] Push notifications fire on configurable intervals (if enabled)
- [ ] Presence indicator shows when other parent is active

---

## Phase 3: Insights + Patterns

**Goal**: Give parents a useful summary of how Miller is doing — totals, trends, patterns — without overwhelming them.

**Effort**: 3 days

### What to Build

#### Daily Summary (0.5 day)
Simple stats block on main screen or dedicated "Today" tab:
- Total feeds today: N (Xh Xm total nursing, X bottles)
- Diapers: N wet, N dirty
- Sleep: N hours Xm total, last woke X ago

#### Weekly Summary (0.5 day)
- `GET /stats/weekly` — aggregate query
- Bar chart: daily sleep hours for last 7 days (recharts)
- Feed frequency heatmap (by hour of day, by day of week)
- Average feeds/day, average sleep/day

#### Feed Pattern Visualization (0.5 day)
- Circular 24-hour clock showing when feeds typically happen
- Color-coded: breast vs bottle
- Useful for predicting next feed window

#### Sleep Pattern Chart (0.5 day)
- Gantt-style timeline: shows sleep blocks across last 7 days
- Longest stretch highlighted (important for new parents tracking "longest sleep")
- Average nighttime sleep duration

#### Growth Tracking (1 day)
- Add weight/height/head circumference logging (separate from events)
- WHO growth chart percentile calculation (built-in lookup table, no external API)
- Simple line chart showing growth trajectory
- "Miller is in the X percentile for weight" 

### Definition of Done — Phase 3
- [ ] Daily stats visible on main screen
- [ ] Weekly summary accessible
- [ ] Growth log + percentile chart working
- [ ] Charts render correctly on mobile (no overflow, touch-friendly)

---

## Phase 4: Smart Features

**Goal**: Reduce cognitive load for exhausted parents by surfacing the right info at the right time.

**Effort**: 3 days

#### "Time Since Last..." Indicators (0.5 day)
Already planned for Phase 1 main screen — Phase 4 upgrades them:
- Animated urgency: text turns amber at 2.5h since feed, red at 3.5h
- "Next feed likely around X" based on average interval

#### Pattern-Based Reminders (1 day)
- Analyze last 7 days' feed intervals per time-of-day
- Calculate personalized reminder threshold (not hardcoded 3h)
- Push notification with context: "Usually feeds around this time — last was 2h 45m ago"

#### Pediatrician Export (1 day)
- `GET /export/pdf` — generates PDF report
- 2-week summary: feeds, sleep, diapers, growth
- Clean, formatted layout (not a data dump)
- Shareable link with 7-day expiry (no auth required to view, but only accessible via link)

#### Notes Field (0.5 day)
- Add optional notes to any event (feed, diaper, sleep)
- Free text, shown in timeline
- Searchable in Phase 5

### Definition of Done — Phase 4
- [ ] Time-since indicators on main screen with urgency coloring
- [ ] Personalized reminders working (based on actual patterns)
- [ ] PDF export covers last 2 weeks, is legible and printable
- [ ] Notes can be added to any event

---

## Phase 5: Nice-to-Haves

**Goal**: Round out for longer-term use and caregiver sharing. Build when Phase 1–4 are stable.

**Effort**: Variable / ongoing

### Features (priority order)

1. **Multiple baby profiles** — add baby button in settings, switch between profiles in header. Database already supports this (all events scoped to `baby_id`).

2. **Caregiver sharing** — invite link generates a `viewer` role. Caregivers see live timeline and stats but cannot log events. Good for grandparents.

3. **Photo milestones** — attach a photo to any event. Store in S3-compatible storage (Backblaze B2 is cheap). Thumbnail on timeline entry.

4. **AI insights** — weekly digest: "Miller slept 30 min more this week than last. Longest stretch: 4h 12m on Wednesday." Simple template-based, no LLM needed for basic version.

5. **Data export (CSV)** — `GET /export/csv` — all events as CSV. Good for paranoid parents who want their data.

6. **Baby monitor integration** — out of scope until there's a clear integration target. Skip.

---

## Build Order & Milestones

```
Week 1  ████████████  Phase 1 MVP
Week 2  ████          Phase 2 Real-Time Sync
        ████          Phase 2 Offline Support
Week 3  ███           Phase 3 Stats
        ██            Phase 4 Smart Features (partial)
Week 4+ ░░░           Phase 4/5 as desired
```

**Milestone 1** (End of Week 1): App on both phones, all three log types working, PWA installed.  
**Milestone 2** (Mid Week 2): Real-time sync live — one parent logs, other sees it instantly.  
**Milestone 3** (End of Week 2): Offline mode working — hospital/weak signal use case solved.  
**Milestone 4** (Week 3): Weekly stats and growth charts visible.

---

## Key Technical Decisions to Revisit

| Decision | Choice | Revisit If |
|---|---|---|
| SQLite vs PostgreSQL | SQLite | Queries slow, need full-text search, multiple babies |
| WebSocket vs SSE | WebSocket | Need broadcast from server only (SSE is simpler then) |
| JWT vs sessions | JWT (30-day) | Need server-side revocation |
| Offline queue in IndexedDB | Yes | Browser storage quota issues (unlikely for event data) |
| Push notifications | Web Push API | Safari support is still inconsistent on iOS |

---

## Risks

**iOS Safari PWA limitations**: Background sync and push notifications on iOS PWA are better in iOS 16.4+ but still inconsistent. Mitigation: in-app polling as fallback, push is opt-in.

**WebSocket on mobile networks**: Mobile connections drop frequently. Mitigation: reconnect with exponential backoff, fall back to 10s polling, offline queue for all writes.

**Timer accuracy when app is backgrounded**: Browser timers throttle in background tabs. Mitigation: store `timer_started_at` timestamp server-side; recompute duration on display rather than tracking elapsed client-side.

**Conflict on simultaneous logging**: Both parents log a feed at the same time (rare but possible). Mitigation: last-write-wins by `created_at`, show both events in timeline (they can delete the duplicate).
