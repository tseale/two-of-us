# SNOO Cloud API (undocumented)

Reference compiled 2026-07-26 from the source code of open-source community clients. The API is **undocumented and unofficial**; Happiest Baby has changed it without notice at least three times (2021 auth rev, ~2024 move to AWS Cognito, **August 2025 PubNub → MQTT realtime change**). Facts below are tagged with the repo/file they came from and a confidence level:

- **verified-in-source (current)** — read from `python-snoo` 0.11.0 (released 2026-01-29, the client used by Home Assistant Core) or HA Core `dev`.
- **verified-in-source (legacy)** — read from older clients (`pysnoo`, `pysnoo2`, `pysnooapi`, `maebert/snoo`); endpoints may still work but reflect the 2020–2022 API generation.
- **inferred** — stated by maintainers/issues/press, not confirmed by reading a request/response in code.

### Sources read

| Client | Era | Source |
|---|---|---|
| `Lash-L/python-snoo` 0.11.0 (current, post-Aug-2025) | 2024–2026 | GitHub repo now returns **404** (deleted or private). Source read from the PyPI sdist: <https://files.pythonhosted.org/packages/d5/fe/20baef11d8e37347af8c5ca86e5d76c607feacd56dc5dc5e52fc30db22ea/python_snoo-0.11.0.tar.gz> (files `python_snoo/snoo.py`, `containers.py`, `baby.py`, `exceptions.py`). PyPI: <https://pypi.org/project/python-snoo/> |
| Home Assistant Core `snoo` integration | current | <https://github.com/home-assistant/core/tree/dev/homeassistant/components/snoo> (`manifest.json` pins `python-snoo==0.8.3`) |
| `rado0x54/pysnoo` (branch `develop`) | 2020–2021 | <https://github.com/rado0x54/pysnoo/blob/develop/pysnoo/const.py>, `snoo.py`, `models.py`, `auth_session.py`, `tests/fixtures/*.json`, `tests/test_snoo_auth_session.py` |
| `DanPatten/pysnoo2` (branch `master`) | ~2022–2023 | <https://github.com/DanPatten/pysnoo2/blob/master/pysnoo2/const.py>, `snoo.py`, `auth_session.py`, `models.py` |
| `sanghviharshit/pysnooapi` (branch `master`) | ~2021 | <https://github.com/sanghviharshit/pysnooapi/blob/master/pysnooapi/const.py>, `api.py`, `device.py`, `errors.py` |
| `maebert/snoo` (branch `master`) | 2019–2020 | <https://github.com/maebert/snoo/blob/master/snoo/client.py>, `README.md` |

---

## A. Authentication

There are **two auth generations**. The current app authenticates against **AWS Cognito**, then exchanges the Cognito IdToken for a Happiest-Baby-specific token.

### A.1 Current auth (AWS Cognito) — verified-in-source (current), `python_snoo/snoo.py`

**Login**

- URL: `POST https://cognito-idp.us-east-1.amazonaws.com/`
- Headers:
  ```
  x-amz-target: AWSCognitoIdentityProviderService.InitiateAuth
  content-type: application/x-amz-json-1.1
  accept: application/json
  accept-language: US
  accept-encoding: gzip
  user-agent: okhttp/4.12.0
  ```
- Body (JSON):
  ```json
  {
    "AuthParameters": {"USERNAME": "<email>", "PASSWORD": "<password>"},
    "AuthFlow": "USER_PASSWORD_AUTH",
    "ClientId": "6kqofhc8hm394ielqdkvli0oea"
  }
  ```
  The `ClientId` is the Happiest Baby app's public Cognito app-client id (hardcoded in python-snoo).
- Response: standard Cognito shape — `AuthenticationResult.AccessToken`, `.IdToken`, `.RefreshToken`, `.ExpiresIn` (seconds; python-snoo defaults to 3600 when absent and schedules refresh at `ExpiresIn - 300`). Wrong credentials → body contains `"__type": "NotAuthorizedException"` (python-snoo raises `InvalidSnooAuth` on this).
- **The `IdToken` (not AccessToken) is what all happiestbaby.com REST calls use**: `authorization: Bearer <IdToken>` (see `generate_snoo_auth_headers()`).

**Refresh**

- Same URL/headers, body:
  ```json
  {
    "AuthParameters": {"REFRESH_TOKEN": "<RefreshToken>"},
    "AuthFlow": "REFRESH_TOKEN_AUTH",
    "ClientId": "6kqofhc8hm394ielqdkvli0oea"
  }
  ```
- Response: `AuthenticationResult` with new `AccessToken`, `IdToken`, `ExpiresIn`; `RefreshToken` is usually **not** returned (python-snoo keeps the old one). ≥400 → treated as invalid auth.
- python-snoo also carries an alternate refresh header set imitating the iOS app: `user-agent: Happiest Baby/2.1.6 (com.happiestbaby.hbapp; build:88; iOS 18.3.0) Alamofire/5.9.1`.

**Happiest Baby token exchange (needed for PubNub legacy realtime; still called during authorize())**

- URL: `POST https://api-us-east-1-prod.happiestbaby.com/us/me/v10/pubnub/authorize`
- Headers: `authorization: Bearer <Cognito IdToken>`, `content-type: application/json; charset=UTF-8`, `user-agent: okhttp/4.12.0`, `accept-language: US`
- Body (device fingerprint blob, values are arbitrary but shape matters):
  ```json
  {"advertiserId": "", "appVersion": "1.8.7", "device": "panther",
   "deviceHasGSM": true, "locale": "en", "os": "Android", "osVersion": "14",
   "platform": "Android", "timeZone": "America/New_York", "userCountry": "US",
   "vendorId": "<random-ish string>"}
  ```
- Response: `{"snoo": {"token": "<snoo token>"}}` (confirmed in both python-snoo `authorize()` and pysnoo2 `pubnub_auth()`).

### A.2 Legacy auth (pre-Cognito) — verified-in-source (legacy)

- `rado0x54/pysnoo` (`const.py`, verified against `tests/test_snoo_auth_session.py`):
  - Login: `POST https://snoo-api.happiestbaby.com/us/login/` with headers `Accept: application/json`, `Content-Type: application/json;charset=UTF-8`, `User-Agent: okhttp/4.7.2`; body `{"grant_type": "password", "username": "<email>", "password": "<password>"}` (OAuth2 ROPC serialized **as JSON**, not form-encoded — the API is "not 100% RFC 6749 compliant").
  - Response (`tests/fixtures/us_login__post_200.json`): `{"access_token": "<JWT>", "expires_in": 10800, "groups": ["Users"], "refresh_token": "...", "scope": "offline_access", "token_type": "Bearer", "userId": "<hex>"}` — **token lifetime 10800 s (3 h)**; pysnooapi's code comments agree ("api returns 3 hours").
  - Refresh: `POST https://snoo-api.happiestbaby.com/us/refresh/`, body `{"grant_type": "refresh_token", "refresh_token": "<token>"}`, same headers; response same shape as login.
  - Login failure fixture (`us_login__post_400.json`): HTTP 400 with `{"error": {"code": 1004, "message": "Email or password is incorrect", "name": "IncorrectPasswordError", "status": 400, "stormpathCode": 7100}}`.
- `sanghviharshit/pysnooapi` (`const.py`, `api.py`): `POST /us/v2/login` and `POST /us/v2/refresh` on the same host, plain body `{"username": ..., "password": ...}` / `{"refresh_token": ...}`, `User-Agent: SNOO/2.4.0 (com.happiestbaby.snooapp;) Alamofire/5.3.0`.
- `DanPatten/pysnoo2` (`const.py`): `POST https://api-us-east-1-prod.happiestbaby.com/us/v3/login` and `/us/v2/refresh/` — shows the host migration from `snoo-api.happiestbaby.com` → `api-us-east-1-prod.happiestbaby.com` and login version bumps v1→v2→v3 before the Cognito cutover.
- Whether the legacy `/us/*/login` endpoints still accept credentials today is **inferred-unknown**; the current app and python-snoo use only Cognito.

---

## B. Devices and Baby

### B.1 Devices — verified-in-source (current), `python_snoo/snoo.py` `get_devices()`

- URL: `GET https://api-us-east-1-prod.happiestbaby.com/hds/me/v11/devices`
- Headers: `authorization: Bearer <IdToken>` + the standard header set above.
- Response: an object whose `"snoo"` key is a list of devices (pysnoo2 `get_devices` also reads `resp_json.get('snoo')`). Device shape (python-snoo `SnooDevice` dataclass): `serialNumber: str`, `firmwareVersion: str`, `babyIds: [str]`, `name: str`, `deviceType: int?`, `presence: {}?`, `presenceIoT: {}?`, `awsIoT: {awsRegion, clientEndpoint, clientReady, thingName}?`, `lastSSID: {}?`, `provisionedAt: str?`. `awsIoT.clientEndpoint`/`thingName` are what the MQTT realtime channel uses (see §E).
- Legacy: `GET https://snoo-api.happiestbaby.com/ds/me/devices/` returned a bare **array** with `serialNumber`, `baby` (single baby id), `createdAt`, `firmwareUpdateDate`, `firmwareVersion`, `lastProvisionSuccess`, `lastSSID {name, updatedAt}`, `timezone` (IANA string), `updatedAt` (rado0x54/pysnoo `const.py` + `tests/fixtures/ds_me_devices__get_200.json`). pysnooapi also used `GET /ds/devices/{serialNumber}/configs` for device config incl. `networkStatus.lastPresence`.

### B.2 Babies — verified-in-source (current), `python_snoo/snoo.py` `get_babies()`, `baby.py`

- List: `GET https://api-us-east-1-prod.happiestbaby.com/us/me/v10/babies` → JSON **array** of babies.
- Single: `GET https://api-us-east-1-prod.happiestbaby.com/us/me/v10/babies/{babyId}`.
- Baby shape (`BabyData`): `_id: str` (the baby id used in other URLs), `babyName`, `birthDate?`, `expectedBirthDate?`, `sex`, `preemie?`, `createdAt`, `updatedAt?`, `startedUsingSnooAt?`, `disabledLimiter: bool`, `pictures: []`, `breathSettingHistory: []`, `settings: {carRideMode: bool, daytimeStart: int, minimalLevel: str, minimalLevelVolume: str, motionLimiter: bool, responsivenessLevel: str, soothingLevelVolume: str, weaning: bool}`. Settings enum values (pysnoo `models.py`): responsiveness/volumes `lvl-2|lvl-1|lvl0|lvl+1|lvl+2`, minimalLevel `baseline|level1|level2`.
- Legacy single-baby endpoint: `GET/PATCH https://snoo-api.happiestbaby.com/us/v3/me/baby/` (pysnoo; PATCH with `{"settings": {...}}` updates weaning, motionLimiter, etc.). pysnoo2: `/us/me/v10/baby`.
- User info (legacy): `GET /us/me` → `{email, givenName, surname, region, userId}` (+ `familyId` in pysnoo2).

### B.3 Journal / activity logging (current, feeding & diapers) — verified-in-source (current), `python_snoo/baby.py`

- Read: `GET https://api-us-east-1-prod.happiestbaby.com/cs/me/v11/babies/{babyId}/journals/grouped-tracking?group=activity&fromDateTime=<ISO-ms-with-offset>&toDateTime=<...>` → array of activities; each has `id`, `type` (`"diaper"`, `"breastfeeding"`, others exist), `startTime`, (`endTime`), `babyId`, `userId`, `data`, `createdAt`, `updatedAt`, `note?`. Diaper `data.types` values: `"pee"`, `"poo"`.
- Write: `POST https://api-us-east-1-prod.happiestbaby.com/cs/me/v11/journals` with `{"babyId": ..., "type": "diaper", "data": {"types": ["pee"]}, "startTime": "<ISO ms, offset required>", "note": "..."}`.

---

## C. Sessions (sleep data)

### C.1 Last/current session

**Legacy shape — verified-in-source (legacy), rado0x54/pysnoo `const.py`, `models.py`, fixture `ss_v2_sessions_last__get_200.json`:**

- URL: `GET https://snoo-api.happiestbaby.com/ss/v2/sessions/last/` (account-wide, no params). pysnooapi variant: `GET /analytics/sessions/last`. **pysnoo2 (newer host) variant: `GET https://api-us-east-1-prod.happiestbaby.com/ss/me/v10/babies/{babyId}/sessions/last`** — per-baby, which is likely the shape the current backend serves.
- Response:
  ```json
  {
    "startTime": "2020-11-21T03:50:06.296Z",
    "endTime": "2020-11-21T03:50:43.025Z",
    "levels": [ {"level": "BASELINE"}, {"level": "LEVEL1"}, {"level": "ONLINE"} ]
  }
  ```
- Timestamps: ISO-8601 **UTC with `Z` suffix and millisecond precision**.
- "Still running" is represented by **`endTime` being absent/null** (pysnooapi `device.py`: `is_on = startTime != None and endTime == None`; pysnoo `LastSession.current_status` returns AWAKE if `end_time` set, else ASLEEP when last level is `BASELINE`/`WEANING_BASELINE`, else SOOTHING).
- No session id in this payload (legacy shape). `levels[-1].level` is the current level while running.

### C.2 Aggregated day history — verified-in-source (legacy), rado0x54/pysnoo + fixture `ss_v2_sessions_aggregated__get_200.json`

- URL: `GET https://snoo-api.happiestbaby.com/ss/v2/sessions/aggregated/`
- Query param: `startTime=YYYY-MM-DD HH:MM:SS.mmm` (format string `%Y-%m-%d %H:%M:%S.%f` truncated to ms; **no timezone — server assumes the account/device-configured timezone**). Returns the 24 h window starting at `startTime`.
- Response:
  ```json
  {
    "daySleep": 24536, "nightSleep": 0, "totalSleep": 24536,
    "longestSleep": 8368, "naps": 4, "nightWakings": 0, "timezone": null,
    "levels": [
      {"isActive": false, "sessionId": "1007201535",
       "startTime": "2021-02-02 07:09:10.215",
       "stateDuration": 8368, "type": "asleep"},
      {"isActive": false, "sessionId": "1198573785",
       "startTime": "2021-02-02 10:43:16.818",
       "stateDuration": 60, "type": "soothing"}
    ]
  }
  ```
  - **All durations in seconds** (pysnoo `models.py` wraps them in `timedelta(seconds=...)`; maebert/snoo README confirms "all durations are given in seconds").
  - `levels[].type` values (`SessionItemType` enum): `"asleep"`, `"soothing"`, `"awake"`.
  - `levels[].startTime`: `YYYY-MM-DD HH:MM:SS.mmm`, local time, no offset.
  - **`sessionId` exists here**: a numeric-looking string grouping segments of one session; `isActive: bool` marks the currently running segment.
- pysnooapi variant (same generation): `GET /ss/v2/babies/{baby_id}/sessions/aggregated/daily?startTime=2021-02-04T08:00:00.000Z&levels=true&detailedLevels=false` — note this one takes ISO-with-Z and has `levels`/`detailedLevels` boolean query params (`detailedLevels=true` returns the finer-grained breakdown; exact detailed shape not captured in any fixture — **inferred**: same item shape with SNOO level strings).

### C.3 Averages and totals — verified-in-source (legacy), pysnoo `const.py`/`snoo.py`, fixture `ss_v2_babies_sessions_aggregated_avg__get_200.json`

- `GET /ss/v2/babies/{babyId}/sessions/aggregated/avg/?startTime=<same fmt as C.2>&interval=week|month&days=true|false` → `{"totalSleepAVG": s, "daySleepAVG": s, "nightSleepAVG": s, "longestSleepAVG": s, "nightWakingsAVG": f, "days": {"totalSleep": [s...], "daySleep": [...], "nightSleep": [...], "longestSleep": [...], "nightWakings": [...]}}` (seconds).
- `GET /ss/v2/babies/{babyId}/sessions/total-time/` → `{"totalTime": <seconds>}`.
- Same paths exist on the new host in pysnoo2 (`https://api-us-east-1-prod.happiestbaby.com/ss/v2/babies/{}/sessions/...`).

### C.4 SNOO level strings — verified-in-source (both generations)

Confirmed exact strings (pysnoo `SessionLevel`, python-snoo `SnooLevels`/`SnooStates`):
`ONLINE` (= device on but not running / "stop"), `BASELINE`, `WEANING_BASELINE`, `LEVEL1`, `LEVEL2`, `LEVEL3`, `LEVEL4`, plus state-machine-only values `PRETIMEOUT`, `TIMEOUT`, `SUSPENDED`, `GLOBAL_SETTINGS`, `UNRECOVERABLE_SUSPENDED`, `UNRECOVERABLE_ERROR`, `NONE`, `MANUAL`.

### C.5 Realtime state (for completeness — this is where the live session id lives)

The realtime `ActivityState` message (MQTT topic `{awsIoT.thingName}/state_machine/activity_state`, formerly PubNub channel `ActivityState.{serialNumber}`) carries: `left_safety_clip`, `right_safety_clip`, `rx_signal {rssi, strength}`, `sw_version`, `event_time_ms` (epoch ms), `system_state`, `event` (`timer|cry|command|safety_clip|long_activity_press|activity|power|status_requested|sticky_white_noise_updated|config_change|restart`), and `state_machine`: `state` (level string above), `up_transition`/`down_transition` (next/prev level or `NONE`), `since_session_start_ms` (ms), `time_left` (s, `-1` = none), **`session_id: str`**, `is_active_session` (`"true"`/`"false"` string in legacy PubNub payloads; bool-ish in python-snoo), `hold`/`audio`/`sticky_white_noise`/`weaning` (`"on"`/`"off"`). (python-snoo `containers.py`, pysnoo `models.py`, pysnoo fixture `pubnub_message_ActivityState.json`.)

Commands are published to `{thingName}/state_machine/control` (formerly PubNub `ControlCommand.{serialNumber}`) as `{"ts": <epoch*1e7>, "command": "start_snoo" | "go_to_state" | "send_status" | "set_sticky_white_noise", ...}` with e.g. `{"state": "LEVEL1", "hold": "on"|"off"}`.

---

## D. Errors, limits, subscriptions, regions

- **401 semantics**: legacy clients treat 401 (pysnooapi) or 401/403 (pysnoo2 `auth_session.py`) as "token expired" → discard token, re-auth, retry once. Cognito login failures surface as HTTP 400 with `__type: NotAuthorizedException` (Cognito) or the legacy `error.name: IncorrectPasswordError` shape. — verified-in-source.
- **Rate limiting**: no explicit 429 handling in any client; HA PR [#150570](https://github.com/home-assistant/core/pull/150570) warns that hammering the broken PubNub path "could lead to rate limits or blacklisting", implying server-side throttling exists but undocumented. — inferred.
- **Token lifetime**: legacy `/us/login` → `expires_in: 10800` (3 h, fixture-verified). Cognito `ExpiresIn` is typically 3600 s; python-snoo refreshes 300 s early. — verified-in-source.
- **Premium subscription**: since mid-2024 Happiest Baby paywalls app features (sleep tracking/history, weaning, some levels) behind a ~$19.99/mo "Premium" subscription ([STAT News](https://www.statnews.com/2024/09/04/snoo-premium-features-sids-insurance/), [Happiest Baby blog](https://www.happiestbaby.com/blogs/snoo/premium-app-features)). **No client source encodes a "subscription required" error response**, so whether `/ss/...` history endpoints return 402/403/empty for non-subscribers is **inferred-unverified** — treat history availability as subscription-dependent. Realtime state and control (the parts HA uses) work without premium.
- **Regions**: only US hosts appear in any client: legacy `https://snoo-api.happiestbaby.com`, current `https://api-us-east-1-prod.happiestbaby.com`, with all paths prefixed `/us/`, `/ds|hds/`, `/ss/`, `/cs/`. The pubnub-authorize body has `userCountry: "US"`. No EU base URL exists in any community source — **unknown/inferred** that EU accounts use the same host.

---

## E. August 2025 API change — what actually changed

Verified via HA Core PR [#150570](https://github.com/home-assistant/core/pull/150570) ("Change Snoo to use MQTT instead of PubNub", shipped in HA 2025.8.2) and the python-snoo 0.6.7 → 0.7.0 source diff (0.7.0 released 2025-08-10):

1. **PubNub realtime broke**: upstream grant change caused persistent PubNub **403 Forbidden** after re-auth (HA issue #150441). Happiest Baby's app had moved realtime to **MQTT over WebSocket against AWS IoT**.
2. **New realtime transport** (python-snoo ≥0.7.0, `subscribe_mqtt()`): connect `wss://{device.awsIoT.clientEndpoint}:443/mqtt`, MQTT **v3.1**, username `?SDK=iOS&Version=2.40.1`, no password, random client id, and WebSocket header `token: <Cognito IdToken>`. Subscribe `{awsIoT.thingName}/state_machine/activity_state`; publish commands to `{awsIoT.thingName}/state_machine/control`. Reconnect requires a fresh IdToken (hence python-snoo restarts MQTT on every token refresh; 0.8.3 fixed reauth bugs).
3. **REST endpoints were NOT changed**: Cognito login/refresh, `/hds/me/v11/devices`, `/us/me/v10/babies*`, `/us/me/v10/pubnub/authorize`, and `/cs/me/v11/journals*` are identical before and after (0.6.7 vs 0.11.0 diff shows only transport, typing, and refresh-robustness changes). The `hds` devices response's `awsIoT {awsRegion, clientEndpoint, clientReady, thingName}` object — present earlier — became load-bearing.
4. PubNub keys (`sub-c-97bade2a-483d-11e6-8b3b-02ee2ddab7fe` / `pub-c-699074b0-7664-4be2-abf8-dcbb9b6cd2bf`, origin `happiestbaby.pubnubapi.com`) remain in python-snoo 0.11.0 as a legacy path but are effectively dead for new grants.

---

## Practical notes for a new client

- Auth with Cognito (`USER_PASSWORD_AUTH`, ClientId `6kqofhc8hm394ielqdkvli0oea`), send the **IdToken** as `Bearer` to `api-us-east-1-prod.happiestbaby.com`, refresh every ~55 min.
- The current-generation REST surface verified working post-Aug-2025 is: devices (`/hds/me/v11/devices`), babies (`/us/me/v10/babies`), journals (`/cs/me/v11/...`), pubnub-authorize. The sleep-session endpoints (`/ss/...`) are only verified in the 2020–2023 clients; the pysnoo2 forms on the current host (`/ss/me/v10/babies/{id}/sessions/last`, `/ss/v2/babies/{id}/sessions/...`) are the best candidates to try first, and results may depend on a Premium subscription.
- For live "is a session running / current level", the MQTT activity_state stream (or its `state_machine.session_id` / `is_active_session`) is more reliable than polling `sessions/last`.

---

## How the Two of Us client (`TwoOfUs/SNOO/`) maps onto this

- **Auth**: Cognito `USER_PASSWORD_AUTH` / `REFRESH_TOKEN_AUTH` (§A.1). The IdToken is stored as the "access token" and sent as `Bearer` to the REST host; refresh runs 300 s before expiry.
- **Baby id**: resolved once at sign-in via `/hds/me/v11/devices` (`babyIds[0]`), falling back to `/us/me/v10/babies` (`[0]._id`); cached in the Keychain blob.
- **Sessions**: `/ss/me/v10/babies/{babyId}/sessions/last` and `/ss/me/v10/babies/{babyId}/sessions/aggregated?startTime=...` — the best-candidate current-host forms. The aggregated path was originally the legacy `/ss/v2/babies/{babyId}/sessions/aggregated/` form; that route was confirmed dead 2026-07-26 (see **route-existence probe** below) and corrected to the `me/v10` sibling of the working `last` endpoint. **The response shape from a 200 is still unverified** — no test-account credentials were available for this probe, only the route's existence; all paths live in `SnooAPIConfig` so a correction is a one-line change. Decoding accepts both `levels` and `detailedLevels`, both ISO-Z and bare-local timestamps.
- **Route-existence probe** (new confidence tier, 2026-07-26): an *unauthenticated* `GET` with a garbage bearer token distinguishes a real route from a dead one without needing valid credentials — API Gateway rejects a bad token on a *registered* route with `403 {"message":"Forbidden"}`, but a path with **no** route mapping falls through to a plain `404` with an Express `Cannot GET ...` HTML body. Confirmed this way: `/hds/me/v11/devices` (403, real), `/us/me/v10/babies` (403, real), `/ss/me/v10/babies/{id}/sessions/last` (403, real), `/ss/v2/babies/{id}/sessions/aggregated/` (**404, dead** — the old path), `/ss/me/v10/babies/{id}/sessions/aggregated` (403, real — the new path). `/ss/me/v11/babies/{id}/sessions/aggregated` also returned 403 if `v10` needs revisiting.
- Manual verification step remaining (Phase 0 exit): sign in with the real account, confirm a real 200 + payload shape on the corrected `/ss/` paths, and capture fixtures into `TwoOfUsTests/` if the shapes differ.
