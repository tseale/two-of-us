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

A live authenticated capture (signing in and watching XHR on the student feed)
hasn't been done yet — the session this research ran in couldn't complete the
1Password credential handoff. It's the one remaining verification step; see
§Open questions.

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

Full JSON shape verified in the export library's models. The fields we care
about:

```jsonc
{
  "object_id": "…",              // stable unique id — our dedupe key
  "action_type": "ac_food",      // taxonomy below
  "event_date": "2026-09-28T11:30:00.000Z",  // when it happened
  "created_at": "…",             // when staff logged it
  "note": "Took 4oz happily",    // free text, often null
  "details_blob": { "tags": ["Wet"] },  // per-type details; loosely typed
  "actor":  { "first_name": "…" },      // staff member who logged it
  "room":   { "name": "Infant A" },
  "media":      { "image_url": "…", "thumbnail_url": "…" },  // photos
  "video_info": { "downloadable_url": "…", "streamable_url": "…" },
  "menu_item_tags": [ … ],       // meals
  "staff_only": false
}
```

`action_type` taxonomy (complete, extracted from the live 2026-09-28 bundle):

| Brightwheel | Two of Us | Notes |
|---|---|---|
| `ac_food` | `FeedEvent` | `details_blob` carries amount/meal info; bottles vs. solids distinguished by tags/menu items — exact keys need a live capture |
| `ac_nap` | `SleepEvent` | start/end/duration in `details_blob`; "still sleeping" state exists in the UI |
| `ac_potty` | `DiaperEvent` | tags like Wet/BM/Dry |
| `ac_photo`, `ac_video` | photo attachment / skip in v1 | media URLs are signed CDN links |
| `ac_note`, `ac_observation`, `ac_kudo` | `NoteEvent` | |
| `ac_checkin` | arrival/departure — display only | |
| `ac_meds`, `ac_health_check`, `ac_health_screen`, `ac_incident` | `NoteEvent` (flagged) | worth surfacing, not worth new models |
| `ac_absence`, `ac_learning_activity`, `ac_activity`, `ac_internal_checkin` | skip | |

Timestamps are UTC ISO-8601; the school's `time_zone` comes with the student
record.

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

## 8. Open questions (next session, ~30 min with Taylor at the keyboard)

1. Sign in on the web app with DevTools open; confirm the exact
   `POST /api/v1/sessions` request/response shape and whether 2FA fires.
2. Run `scripts/brightwheel_sync.py` with the harvested cookie: verify the
   guardian endpoints, capture real `details_blob` shapes for `ac_food` /
   `ac_nap` / `ac_potty` (the one piece of the schema we can't get from
   static analysis), and pin down bottle-oz representation.
3. Leave the cookie in place and re-run daily for a week: measure cookie
   lifetime, and test the same cookie from a second IP/device to answer the
   shared-credentials question.
