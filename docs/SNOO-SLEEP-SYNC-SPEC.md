# SNOO Sleep Sync — Engineering Design Spec

> Implementation brief, provided verbatim 2026-07-26. Note: §12's "commit to
> staging branch" predates the removal of `staging` (2026-06-19); work happens
> on the `snoo-sleep-sync` feature branch instead.

## 1. Summary

SNOO Sleep Sync lets the user connect their Happiest Baby account in Settings.
On app foreground, it quietly fetches recent SNOO session history from the
Happiest Baby cloud, compares it against sleep sessions already logged in the
app, and surfaces non-intrusive suggestion cards for anything the SNOO recorded
that the app doesn't know about.

Two suggestion shapes:

- **Completed session** (has start + end): "Save a SNOO session" — pre-filled
  sleep record
- **In-progress session** (start, no end): "Start a sleep session" — backdated
  to SNOO start time

Design intent: the app SUGGESTS, the user CONFIRMS. SNOO data is never written
silently.

## 2. Goals

- Sign in to Happiest Baby account from Settings, sign out
- Persist credentials/tokens in iOS Keychain, refresh transparently
- On app foreground, fetch recent SNOO sessions, reconcile against local sleep
- Surface suggestion cards for unreconciled sessions
- Single-tap accept with option to edit times
- Permanent dismiss — never resurface rejected sessions
- Never duplicate manually logged sleep
- Degrade gracefully when offline, rate-limited, or API changed

### 2.2 Non-goals for v1

- No real-time triggers (poll-on-open only)
- No background monitoring / MQTT
- No SNOO control (read-only)
- No HomeKit output
- No HealthKit writes
- Single SNOO only

## 3. Background — UNDOCUMENTED API

This integrates with an **undocumented, unofficial** Happiest Baby API. No
public API exists. Everything is derived from open-source community clients
(Lash-L/python-snoo, pysnoo2, pysnocapi). API changed materially in August 2025
(PubNub to MQTT). Design every code path to fail soft.

We use the REST API only (not MQTT). Stateless request/response over HTTPS.

## 4. Architecture

Components:

- **SnooAPIClient** (actor) — all network I/O. Login, token refresh, device
  list, session history. Returns typed models or typed errors.
- **SnooTokenStore** — Keychain read/write of tokens. Handles sign-out wipe.
- **SnooReconciler** — Pure function: (SNOO sessions, local sessions, sync
  state) → [Suggestion]. No I/O. All interesting logic and unit tests here.
- **SnooSyncCoordinator** (@MainActor, ObsObj) — orchestration and throttling.
  Owns observable suggestion list. Applies accepted suggestions to SleepStore.
- **SnooSyncState** (UserDefaults) — lastSyncAt, dismissedSessionIDs,
  importedSessionIDs.

Concurrency:

- SnooAPIClient is an actor; all methods async throws
- Token refresh is single-flight (hold in-flight Task, others await it)
- SnooSyncCoordinator is @MainActor for SwiftUI
- SnooReconciler is pure, synchronous, static — trivially testable

## 5. Authentication

**Auth flow:** POST {BASE}/us/login with email + password → access token +
refresh token. Tokens are short-lived (~3 hours). Treat refresh as best-effort
with re-login as fallback.

**Token lifecycle:**

1. On login: persist access token, refresh token, expiry, email to Keychain.
   NEVER persist password. A login response without a refresh token is a
   FAILED connect (it can't outlive the hour or be shared — see §5.1).
2. Before each request: if token expires within 60 seconds, refresh proactively
3. On 401: attempt one refresh and retry
4. If refresh fails: clear tokens, set .needsReauth, passive prompt in Settings
5. On sign-out: delete all Keychain items, clear cached sessions, reset
   SnooSyncState EXCEPT importedSessionIDs

### 5.1 Household connection (one sign-in, every phone)

Added Aug 2026 (commit 76ea509 + the shared-signup hardening PR). The
household shares ONE Happiest Baby account: one parent signs in, every
participant's device adopts the connection. Nobody else ever types SNOO
credentials.

- **What travels:** `SharedSettings.snooCredentials` carries a JSON blob
  (`SnooSharedCredentials`: refresh token, email, babyID, autoLog) through
  the shared CloudKit zone — the same trust boundary as the baby data. Never
  the password, never the short-lived IdToken (each device mints its own;
  Cognito refresh tokens are multi-use and un-rotated, docs/SNOO-API.md §A.1).
- **Three-state field:** `nil` = never written (a signed-in pre-feature
  device PUBLISHES its session so the household inherits it); `""` = explicit
  sign-out (terminal — every device disconnects, and conflict resolution
  must never resurrect a blob over it); JSON = connected (a device out of
  step ADOPTS it into its Keychain).
- **Adoption triggers:** every app-foreground (before the sync throttle),
  and reactively from the Settings SNOO section (`@Query` on the settings
  row) when the record lands mid-session. Expected latency: "Connected" on
  the second phone within one CloudKit delivery of the sign-in — the
  Settings row must never require a background/reopen cycle to update.
- **Publish visibility:** while the settings save is still queued (offline,
  engine down, schema-rejected park) the owner's row shows "Connecting
  other phones…" — local "connected" must not masquerade as household
  connected.
- **Sign-out:** writes `""` (fails LOUDLY if there's no settings row — the
  device then stays connected rather than pretending), then disconnects
  locally. Other phones disconnect on their next adoption trigger. Sign-out
  does NOT revoke the Cognito token server-side (no such endpoint) — the
  account owner can rotate their Happiest Baby password to force that.
- **Leaving the household:** leave/revoke/delete-everything tears down the
  local SNOO connection with the rest of the zone data — an ex-member's
  phone must not keep polling the owner's bassinet or re-seed the token
  into a future household via the publish-local migration.
- **Singleton hygiene:** all readers resolve the settings row via
  `SharedSettings.canonical` (deterministic across devices), and
  `SyncManager.mergeDuplicateSettingsIfNeeded` folds duplicate rows.

**Keychain storage:** Service "com.taylorseale.twoofus.snoo",
kSecAttrAccessibleAfterFirstUnlock

**Security: NEVER write tokens or password to UserDefaults. Never log
tokens/password/response bodies in release. Never store password for
"remember me".**

**Settings UI — 4 states:**

- Not connected: "SNOO" with grey "Not connected", tap → login sheet
- Connected: email as detail, "Last synced" subtitle, tap → detail with Sync
  now + Sign out
- Needs reauth: amber "Sign in again", tap → login sheet with email pre-filled
- Syncing: same as Connected with progress indicator

**Login sheet:** Email + SecureField password, "Connect" button, disclaimer
"Not affiliated with or endorsed by Happiest Baby", inline errors

## 6. API Client

**Endpoints (all UNVERIFIED — confirm against community sources first):**

- Login: POST /us/login
- Refresh: POST /us/refresh
- List devices: GET /ds/me/devices
- List babies: GET /us/v3/me/baby (optional)
- Last/current session: GET /ss/v2/sessions/last
- Aggregated day: GET /ss/v2/sessions/aggregated?startTime=...

**Authorization header:** `Bearer <access token>`

**Response models:**

```swift
enum SnooLevel: String, Codable, Sendable {
    case online = "ONLINE", baseline = "BASELINE", weaningBaseline = "WEANING_BASELINE"
    case level1 = "LEVEL1", level2 = "LEVEL2", level3 = "LEVEL3", level4 = "LEVEL4"
    var isSoothing: Bool { self != .online }
}

struct SnooSession: Identifiable, Hashable, Sendable {
    let id: String  // sessionId, or synthesised stable ID
    let startedAt: Date
    let endedAt: Date?  // nil == still running
    let levels: [SnooLevel]
}

enum SnooAPIError: Error, Sendable {
    case invalidCredentials, needsReauth, rateLimited(retryAfter: TimeInterval?)
    case noDeviceOnAccount, subscriptionRequired
    case decoding(underlying: Error, endpoint: String)
    case transport(underlying: Error), server(status: Int)
}
```

## 7. Sync and Reconciliation Algorithm

**Trigger:** .onChange(of: scenePhase) when .active. Throttled to 5-minute
minimum. Check connectivity first. No sync if already in flight.

**Fetch and normalise:**

1. Fetch last session (authoritative for in-progress)
2. Fetch aggregated day for today AND yesterday (covers midnight-spanning
   sleep)
3. Convert detailedLevels entries type "asleep" into SnooSession
   (endedAt = startTime + stateDuration)
4. Merge with last-session, de-duplicate on session ID
5. Stable IDs: use sessionId if present, else synthesise
   "snoo-" + ISO8601(startedAt)
6. Drop sessions shorter than 5 minutes (noise)

**Reconciler filter chain (all must pass):**

1. Drop if importedSessionIDs contains the ID
2. Drop if dismissedSessionIDs contains the ID
3. Drop if duration < 5 minutes (completed only)
4. Drop if overlaps any local sleep session by >50%
5. Drop in-progress if any local session is currently open
6. Drop in-progress if started >14 hours ago

Surviving sessions → suggestions. Cap visible list at 3, most recent first.

**Overlap test:** Pure function computing fraction of SNOO session covered by
any local sleep session.

## 8. User Interface

**Suggestion cards** appear at top of sleep-logging surface. Scrollable, not
modal.

**Completed session card:**

- "SNOO recorded a sleep session"
- Time range + duration
- [Save session] [Edit] [×]
- Save: writes sleep record, adds to importedSessionIDs
- Edit: opens sleep editor pre-filled with SNOO times
- ×: adds to dismissedSessionIDs permanently

**In-progress session card:**

- "SNOO has been running since [time]"
- "Start a sleep session from then? (X hr Y min ago)"
- [Start from <time>] [Edit] [×]
- Start: creates open sleep session backdated to SNOO start
- Elapsed time computed at render, not ticking live

**Times in device local timezone, user's 12/24-hour preference. Never UTC.**

## 9. Failure Handling

- Every failure mode is **silent and non-blocking**
- Schema drift: decode defensively, only startTime is required, catch
  .decoding errors
- After 3 consecutive decoding failures: set "integration degraded" flag, show
  neutral text in Settings only
- Error-to-message mapping: invalidCredentials → "That email or password
  didn't work." (inline in login), needsReauth → Settings row only,
  rateLimited → "Syncing paused briefly", etc.
- No automatic retry beyond single post-refresh retry on 401
- On 429: honour Retry-After or back off to 30-min floor, doubling to 4-hour
  ceiling

## 10. Account Safety

- Poll on foreground with 5-minute floor, nothing else
- 3 requests per sync maximum
- Read-only in v1
- Honest User-Agent
- Include "Not affiliated with or endorsed by Happiest Baby" disclaimer
- Keep behind a feature flag for easy removal if requested
- Be prepared for the integration to break at any time

## 12. Implementation Plan

**Phase 0 — Verification (FIRST):**
Read python-snoo, pysnooapi, rado0x54/pysnoo source. Issue authenticated
requests to confirm endpoints. Save fixtures. Record findings in SNOO-API.md.

**Phase 1 — Auth and Settings:**
SnooTokenStore, SnooAPIClient (login, refresh, single-flight, typed errors),
Settings row + login sheet (all 4 states). Exit: user can sign in, cold launch
stays authenticated, sign-out cleans up.

**Phase 2 — Fetch and Reconcile:**
Device list, last session, aggregated day. Normalisation into SnooSession.
SnooReconciler with full unit test suite (§13). SnooSyncState persistence.
Exit: reconciler produces correct suggestions from fixtures.

**Phase 3 — Suggestion UI:**
Both card variants, accept/edit/dismiss. Wire into existing sleep store and
editor. Foreground trigger and throttle. Exit: real SNOO session appears as
card and saves correctly.

**Phase 4 — Hardening:**
Full error-to-message mapping, degraded-integration flag, backoff. Log
redaction audit. Timezone/DST/midnight verification. Disclaimer copy.

## 13. Testing

Exhaustive reconciler unit tests (pure function, no network). Decoding tests
against fixtures. Client integration tests (401 → refresh, single-flight,
backoff). Manual QA checklist.
