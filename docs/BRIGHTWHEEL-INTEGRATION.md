# Brightwheel Integration (research + prototype)

Miller's daycare logs feeds, naps, diapers, photos, and notes in Brightwheel.
This doc maps Brightwheel's **unofficial, internal** API and sketches how those
events would flow into Two of Us — **on-device in Swift**, mirroring the SNOO
integration (`TwoOfUs/SNOO/`, docs/SNOO-API.md), not via a Mac-mini sidecar.

Researched 2026-09-28. Brightwheel has no public API and no published terms for
programmatic access; everything below is reverse-engineered and can break
without notice.

### Sources

| Source | What it establishes | Confidence |
|---|---|---|
| [minormending/brightwheel](https://github.com/minormending/brightwheel) (PyPI `brightwheel`) | Guardian-side endpoints, cookie auth, full activity JSON model | verified-in-source |
| [remotephone/brightwheel-crawler](https://github.com/remotephone/brightwheel-crawler) | Login flow selectors, bot-detection/CAPTCHA behavior, 2FA prompt | verified-in-source |
| Live web app bundle (`cdn.mybrightwheel.com/static/assets/bootstrap.*.chunk.js`, fetched 2026-09-28) | Current endpoint paths, full `action_type` taxonomy, query params, 2FA fields, API v1/v2 split | verified-in-bundle |
| Live sign-in page (`schools.mybrightwheel.com/sign-in`) | Form fields, first-party bot-detection script (`/v5XrMIJ5/init.js`), New Relic, Stripe | observed |
| [pmartindev/brightwheel-home-assistant](https://github.com/pmartindev/brightwheel-home-assistant) (`coordinator.py`, `sensor.py`) | **Authoritative per-type shapes** (current API): bottle `food_type`/`amount`/`amount_type`, nap start/end `state` pairing, `potty_type`/`potty_extras`, **`end_date` exclusive** | verified-in-source |
| [ChaseBro/brightwheel-takeout](https://github.com/ChaseBro/brightwheel-takeout) (tests + scraper) | Wire fixtures: `actor`/`target` shape, non-numeric `amount` values ("most"), `ac_bathroom`/`ac_medication` kinds, per-kind `action_type` query filter | verified-in-source |
| [stephenyeargin/hubot-brightwheel](https://github.com/stephenyeargin/hubot-brightwheel) | Corroborates `potty_type`/`potty_extras` and nap `state` semantics across a five-year gap (stable core); `menu_item_tags[].name` objects | verified-in-source (legacy) |

**Live verification (2026-09-28):** the WKWebView sign-in + cookie harvest
shipped in the app (PR #193/#194) and worked against Taylor's real guardian
account: `/users/me`, the guardian→students lookup (resolved Miller), and
`/students/{id}/activities` all returned 200 with the cookie alone. The
activities response confirmed the pagination wrapper exactly as modeled:
`{"activities": [], "count": 0, "offset": 0, "page": 0, "page_size": 100}`
(empty because Miller hasn't started daycare yet). Still unverified: real
per-activity `details_blob` shapes — blocked on his first day — and cookie
lifetime (clock started 2026-09-28).

## 1. Authentication

- The web app is a Rails-style backend at `https://schools.mybrightwheel.com`.
  All API calls are authenticated by a session cookie named **`_brightwheel_v2`**
  (verified-in-source: the PyPI library does nothing but replay this cookie).
- Sign-in: the SPA POSTs to `/api/v1/sessions` (bundle shows `"/sessions"` and
  `"/sessions/cookies"` under the v1 API root). Guardian accounts sign in with
  email/phone + password.
- **2FA exists**: the bundle has `2fa_required`, `2fa_code`, `verification_code`
  strings, and the crawler README confirms an emailed-code prompt after
  password login. Assume some accounts (or new-device logins) will hit it.
- **Bot detection on sign-in**: the sign-in page loads a first-party
  fingerprinting/bot-detection script (`/v5XrMIJ5/init.js`, a
  PerimeterX/HUMAN-style first-party path), and the crawler project moved to
  `undetected-chromedriver` because plain Selenium logins started getting
  CAPTCHA-challenged. A bare `URLSession` POST to `/api/v1/sessions` may work
  (unverified) but is exactly the kind of request this tooling exists to block.
- **Cookie lifetime**: not formally known. Community usage (the export
  library's whole workflow is "copy the cookie once, then run") implies weeks+
  of validity. Needs measurement — see §Open questions.

### What this means for iOS

Don't fight the bot detection with raw HTTP. Sign in **once through a real
browser context** — a `WKWebView` login sheet pointed at
`schools.mybrightwheel.com/sign-in` — and then harvest `_brightwheel_v2` from
`WKWebsiteDataStore.httpCookieStore`. The user (or daycare's) 2FA and any
CAPTCHA render naturally inside the web view; we never touch the password.
After that, every API call is plain `URLSession` with the cookie attached.
This is *more* honest than the SNOO integration's credential handling (there
we replay email/password against Cognito; here we never see the password at
all).

## 2. Endpoints (guardian-side, API v1)

Base: `https://schools.mybrightwheel.com/api/v1`
Auth: `Cookie: _brightwheel_v2=<value>` on every request.

| Endpoint | Purpose | Notes |
|---|---|---|
| `GET /users/me` | Current user → `object_id` (guardian id), name, email | verified-in-source |
| `GET /guardians/{guardian_id}/students?include[]=schools` | Students visible to this guardian → `students[].student.object_id`, name, birthday, school incl. `time_zone` | verified-in-source |
| `GET /students/{student_id}/activities` | **The daily report.** Paginated activity feed | verified-in-source + bundle |
| `GET /rooms/{room_id}/activities` | Room-level feed (staff-side; not needed) | bundle |
| `GET /students/{student_id}/feed`, `/summaries` | Feed/summary variants the SPA also uses | bundle, shapes unverified |

`GET /students/{id}/activities` query params (library + bundle):

- `page` (0-based), `page_size` (library uses up to 1000)
- `start_date`, `end_date` — the SPA's feed filter sends these; ISO dates
- `action_type` — optional filter, one of the taxonomy below
- `include_parent_actions` — `false` to see only staff-logged entries

The school-admin side of the bundle is migrating to `/api/v2/...` for some
school endpoints; every guardian-facing path above is still v1. There is also a
sandbox host in the bundle (`schools.sandbox.bwtest.net`) — Brightwheel's own
test env, not accessible to us.

## 3. Activity model

Full JSON shape assembled from the export library's models plus the three
parser sources above (2026-09-28 pass). The fields we care about:

```jsonc
{
  "object_id": "…",              // stable unique id — our dedupe key
  "action_type": "ac_food",      // taxonomy below
  "event_date": "2026-09-28T11:30:00.000Z",  // when it happened (UTC ISO-8601)
  "created_at": "…",             // when staff logged it
  "note": "Took 4oz happily",    // free text, often null
  "state": "1",                  // NAPS ONLY: "1" fell asleep / "0" woke up —
                                 // sometimes inside details_blob instead
  "details_blob": { … },         // per-type payload, shapes below
  "menu_item_tags": [ { "name": "Bottle" } ],
  "actor":  { "object_id": "…", "first_name": "…" },  // staff member
  "target": { "object_id": "stu-…" },                 // the student
  "room":   { "name": "Infant A" },
  "media":      { "image_url": "…", "thumbnail_url": "…" },  // photos
  "video_info": { "downloadable_url": "…", "streamable_url": "…" },
  "staff_only": false
}
```

Per-type `details_blob` shapes (HA integration = current API, hubot agrees on
the potty shape since 2019):

- **Bottles** (`ac_food`): `{ "food_type": "bottle", "amount": 4.0,
  "amount_type": "oz" }` — `amount` can arrive as a number or string, and for
  solids can be a *word* ("most"), so parse defensively; `amount_type` can be
  `ml`. Solid food carries `menu_item_tags` and no `food_type: "bottle"`.
- **Naps** (`ac_nap`): **a nap is TWO activities** — fell-asleep
  (`state: "1"`) and woke-up (`state: "0"`), each with its own `object_id`
  and `event_date`, paired by chronological adjacency. There is no
  start/end-in-one-record form (the bundle's `start_time`/`end_time` strings
  are UI form fields, not API fields).
- **Diapers** (`ac_potty`, also `ac_bathroom` for older kids):
  `{ "potty_type": "wet" | "bm" | "dry", "potty_extras": ["diaper_cream", …] }`.

`action_type` taxonomy (complete, extracted from the live 2026-09-28 bundle;
takeout adds `ac_bathroom`/`ac_medication` as query-filter kinds):

| Brightwheel | Two of Us | Notes |
|---|---|---|
| `ac_food` | `FeedEvent` (bottles) / `NoteEvent` (solids) | bottle detection: `food_type`, note keywords, or absent menu items |
| `ac_nap` | `SleepEvent` | start/end pair → one completed sleep, keyed on the woke-up id |
| `ac_potty` | `DiaperEvent` | wet/bm from `potty_type` (+extras); dry checks import as notes |
| `ac_bathroom` | `PottyEvent` | toilet, not diaper (older-kid rooms); outcome from keywords |
| `ac_photo`, `ac_video` | `MediaEvent` | signed CDN URL stored; **local byte caching is a later phase**, rows fall back to a placeholder when the link expires |
| `ac_checkin` | `CheckEvent` | in/out from tags/note; "by Dad/Mom" parses into `byName`; feeds "hours at daycare" |
| `ac_activity`, `ac_learning_activity` | `ActivityEvent` | type from keywords (tummy time, reading…); `duration` blob key is speculative |
| `ac_meds`, `ac_medication` | `MedicationEvent` | `medication_name`/`dosage` blob keys are speculative — verify on first real day |
| `ac_health_check`, `ac_health_screen` | `HealthCheckEvent` | temp/weight from `temperature` blob key (speculative) or note regex; else `StaffNoteEvent` |
| `ac_observation` + development-domain tag | `MilestoneEvent` | "Rolled over!" + [Physical] |
| `ac_note`, `ac_observation`, `ac_kudo`, `ac_incident` | `StaffNoteEvent` | quote-card style, staff author from `actor` |
| `ac_mood`, `ac_milestone` | `MoodEvent` / `MilestoneEvent` | ⚠️ SPECULATIVE action types — not in the 2026-09-28 bundle taxonomy; handled defensively if they ever appear |
| `ac_absence`, `ac_internal_checkin` | skip | |

The nine daycare-era models (activity, media, check-in/out, medication,
health check, mood, potty, milestone, staff note) landed as full SwiftData
models with CloudKit sync (their own record types — detected via the
`RecordType.all` growth, no `schemaGeneration` bump), timeline rows with
per-type accents, report-card aggregates, and mock-day coverage. ⚠️ Before
real installs sync daycare data, push the new record types to the CloudKit
schema (cktool, same dance as PR #145's deploy).

Timestamps are UTC ISO-8601 (fractional seconds usually, not always); the
school's `time_zone` comes with the student record.

**Query gotcha (verified in the HA integration): `end_date` is EXCLUSIVE.**
Fetching today means `start_date = today, end_date = tomorrow` — start ==
end returns nothing. The activities endpoint also accepts an `action_type`
filter for per-kind fetches.

## 4. Prototype

`scripts/brightwheel_sync.py` (stdlib-only) implements the full read path:
cookie → `/users/me` → student lookup → today's activities → normalized JSON
(`brightwheel_import.json`) with the mapping above. Details parsing is
deliberately defensive — unknown `details_blob` keys are passed through under
`raw` so the first real run teaches us the exact schema.

To run it (until the Swift client exists, this is also the fastest way to
finish the endpoint verification):

1. Log into `schools.mybrightwheel.com`, copy the `_brightwheel_v2` cookie
   value from DevTools.
2. `BRIGHTWHEEL_COOKIE=… python3 scripts/brightwheel_sync.py`

## 5. iOS architecture (mirrors `TwoOfUs/SNOO/`)

New module `TwoOfUs/Brightwheel/`:

- **`BrightwheelAPIClient`** (actor) — `URLSession` + the cookie; endpoints in
  a `BrightwheelAPIConfig` struct so path corrections are one-liners, exactly
  like `SnooAPIConfig`. Read-only in v1. Honest User-Agent
  (`TwoOfUs-iOS (unofficial personal Brightwheel integration)`) — with the
  caveat that if the API turns out to gate on browser UAs, we reuse the web
  view's UA instead and note it here.
- **`BrightwheelLoginSheet`** — `WKWebView` on the real sign-in page; on
  navigation to the app shell, read `_brightwheel_v2` from the cookie store,
  then `GET /users/me` + students to resolve Miller's `student_id`. Password
  never touches our code (improvement over SNOO's login sheet).
- **`BrightwheelCredentialStore`** — cookie in Keychain locally; shared across
  the household as a JSON blob field on `SharedSettings`
  (`brightwheelCredentials`), exactly like `snooCredentials`: cookie value,
  signed-in email, `studentID`, `signedInAt` for the same
  sign-out-vs-fresh-sign-in conflict rule. ⚠️ Adding the CloudKit field means
  a **`schemaGeneration` bump** (same dance as PR #145) and a cktool schema
  push before it ships. Open question first: whether one cookie works from two
  devices concurrently (Rails session cookies usually do, but Brightwheel's
  bot tooling may bind sessions to fingerprints — verify before building the
  shared blob; fallback is each parent signing in once in their own web view,
  which is honestly fine).
- **`BrightwheelSyncCoordinator`** — foreground-triggered fetch (app open +
  pull-to-refresh on Today), like SNOO's coordinator; add `BGAppRefreshTask`
  later if it earns it. Fetch window: today ± 1 day.
- **`BrightwheelReconciler`** — pure function, no I/O, unit-tested, same shape
  as `SnooReconciler`: `(activities, local events, importedIDs, dismissedIDs,
  now) → suggestions`. Reuse the PR #190 lessons directly: per-device
  `importedIDs` keyed on Brightwheel `object_id`, overlap filtering against
  local events so a manually-logged feed doesn't duplicate the daycare's entry.
- **Suggestion vs. auto-log** — start with the SNOO suggestion-card flow;
  daycare days produce ~10 events/day, so an "import all" affordance (or the
  `autoLog` household flag pattern) matters more here than it did for SNOO.

### SwiftData changes (all additive)

- `FeedEvent`, `DiaperEvent`, `NoteEvent`: add `sourceRaw: String?` — the
  field `SleepEvent` already has — plus `.brightwheel` cases in the source
  enums (`SleepSource` gains one too). Nil-tolerant, so no migration; CloudKit
  field additions ride the same `schemaGeneration` bump as the credentials
  blob.
- `externalID: String?` on the event models (the Brightwheel `object_id`) so
  dedupe survives re-imports and re-installs; SNOO currently tracks
  imported IDs in sync state only — Brightwheel's higher volume justifies the
  field. Also additive.
- Events imported from Brightwheel sync through the normal CloudKit zone like
  any hand-logged event — only one parent's device needs the integration
  connected for both to see the data.

## 6. Reliability

- **This will break eventually.** The API is unversioned-for-us, internal, and
  the crawler's history shows Brightwheel actively hardening against
  automation. The v1→v2 migration visible in the bundle is the likely first
  breakage: guardian endpoints moving to v2 shapes.
- Blast radius is contained by design: read-only, suggestion-gated, and all
  parsing behind DTOs (`BrightwheelDTOs`) that treat every field as optional —
  a schema change degrades to "no suggestions today," never to bad data in
  SwiftData. Same failure posture as SNOO.
- A `BrightwheelRouteProbe` diagnostic (mirroring `SnooRouteProbe`) is worth
  building on day one given the v2 migration underway.
- Cookie expiry surfaces as 401/403 → clear stored cookie, show a "reconnect
  to Brightwheel" state in Settings, one tap to re-run the login sheet.

## 7. Privacy

- Data is about Miller and is already ours to see as guardians; we're moving
  it between two apps we already use. Read-only access changes nothing on
  Brightwheel's side.
- The cookie is a full-account credential (messages, billing, photos) — treat
  it like a password: Keychain only on device, CloudKit shared zone only if
  the multi-device question in §5 resolves in favor of sharing (the zone is
  already the household trust boundary for `snooCredentials`).
- Photos: activity media URLs are signed CDN links; if we import photos we
  download and store them ourselves (SwiftData/CloudKit asset) rather than
  hot-linking — links likely expire.
- ToS: automated access almost certainly violates Brightwheel's terms of
  service. Personal, read-only, low-volume use of our own child's data is the
  most defensible possible version of that, but it's still their call; the
  realistic worst case is the account getting flagged or the integration
  silently breaking. Worth knowing before building the fancy version.
- App Store: an unofficial-API integration in a TestFlight/App Store build is
  fine technically (it's just HTTPS), but keep it OFF by default and out of
  App Store marketing copy — same posture as SNOO.

## 8. Open questions

1. ~~Verify sign-in and the guardian endpoints~~ — **done 2026-09-28** via the
   in-app WKWebView flow (see Live verification above). Sign-in analysis of
   `POST /api/v1/sessions` is moot: the app never talks to that endpoint, the
   web view does.
2. ~~details_blob shapes~~ — **resolved 2026-09-28** from the
   brightwheel-home-assistant integration + takeout fixtures (see §3); the
   Swift DTOs/mock now speak that wire format. Remaining residual: confirm
   against Miller's own first-day dump ("Fetch today's report (raw)") that
   his school's staff app emits the same shapes — corrections, if any, are
   localized to `BrightwheelDTOs`/`BrightwheelImporter`.
3. Cookie lifetime: signed in 2026-09-28; note the date if a fetch ever comes
   back 401/403. Test the same cookie from the second phone before deciding
   on the shared-CloudKit-blob design (§5).
