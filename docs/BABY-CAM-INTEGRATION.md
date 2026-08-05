# Baby Cam Integration — eufy Baby Monitor E21

Research compiled **2026-08-05** on whether the eufy Baby Monitor E21 can be surfaced inside Two of Us, and if so, how.

**Device under test**

| | |
|---|---|
| Model | eufy Baby Monitor E21 (SKU E8354121, model family **T8354**) |
| Serial | `T8354P20251006EC` |
| LAN address | `192.168.86.66` (router DNS name: `eufy_baby_camera.lan`) |
| MAC | `90:BF:D9:2E:12:F1` |
| Firmware | 2.4.3.7 |
| Companion app | **eufy** (the unified app) — the legacy eufy Baby app is being retired; see below |

> ### ⚠️ App consolidation — read this first
>
> eufy has folded five apps (eufy Security, eufy Clean, eufy Life, **eufy Baby**, eufy Pet) into a single unified app now listed simply as **"eufy"** on the App Store. Per eufy's own [Introduction to New eufy App](https://service.eufy.com/article-description/Introduction-to-New-eufy-App), it *"includes all the features of eufy Security but also integrates the key functionalities of eufy Clean, eufy Life, eufy Baby, and eufy Pet."*
>
> **All integration in this document targets the unified `eufy` app, not the legacy `eufy Baby` app.** Taylor confirmed the Baby app is on its way out, and the evidence agrees: the `NAS(RTSP)` setting that Option 2 depends on exists *only* in the unified app, and eufy's separate "eufy Mega" backend migration is retiring the legacy APIs.
>
> ⚠️ One honest caveat: **eufy has not published a sunset date.** Their support article still says users of the non-Security legacy apps *"can continue using both the old app and the new eufy App simultaneously."* So the direction of travel is unambiguous, but don't plan around a specific cutoff — build against the unified app because it's where the functionality is, not because the old app is guaranteed to stop working on a known date.

**Confidence tags used throughout**

- **[M]** — *measured here*, first-hand on Taylor's Mac mini / LAN on 2026-08-05. Reproducible.
- **[V]** — *verified* from a primary source (vendor doc, Apple API, source code, GitHub thread) with a citation.
- **[L]** — *likely*: strong inference, not directly confirmed.
- **[U]** — *unknown*: no evidence found either way. Called out rather than guessed.

---

## TL;DR

There is **one real path to live video in Two of Us, and it is local RTSP** — not deep links, not HomeKit, not the eufy cloud, and not the P2P stack every Homebridge/Home Assistant integration is built on.

The E21 runs an **RTSP server on the camera itself** (port 554, path `/live0`), which is unlocked by a `NAS(RTSP)` setting that exists only in the **unified `eufy` app**, not the legacy eufy Baby app. Two independent users confirmed this working on E20/E21 hardware in January 2026 [V]. No HomeBase, no cloud in the video path, no reverse engineering.

That the setting lives only in the unified app is a happy alignment: the app consolidation pushes us toward the same app the streaming path already requires.

The catch is reliability: eufy cameras deliberately stop publishing RTSP after a few minutes, and the "Continuous recording" workaround that fixes it is community-discovered, undocumented by eufy, and reported as still-flaky by some users through 2026 [V]. **This has not been verified on Taylor's actual unit.**

**Recommendation — two phases:**

1. ~~**Ship Option 6 now.**~~ ✅ **Built 2026-08-05** — a camera button on the SNOO sleep card that opens the unified `eufy` app. Always works, zero risk, and it stays useful even if RTSP pans out, since in-app video would be LAN-only.
2. **Run the Option 2 verification spike** (protocol below, ~30 minutes with the phone in hand). If RTSP holds a stable stream on Taylor's E21 for an hour, in-app video becomes a real project. If it doesn't, Option 6 is the permanent answer and we've spent half an hour finding out.

| # | Option | Feasibility | Complexity | Reliability | UX | Verdict |
|---|---|---|---|---|---|---|
| 1 | Deep link to camera view | ❌ Blocked | — | — | — | Specific-camera deep link doesn't exist |
| 2 | **Local RTSP streaming** | 🟡 **Promising, unverified** | High | ⚠️ **The open question** | ✅ Excellent | 🔬 **Spike this** |
| 3 | HomeKit | ❌ Direct: blocked | Medium | — | — | No native HomeKit; possible indirectly via 5 |
| 4 | eufy cloud API | ❌ Blocked | Very high | Very low | — | No API; Baby line unsupported; ToS violation |
| 5 | Homebridge / Scrypted relay | 🟡 Viable **via RTSP only** | Medium | Inherits Option 2's risk | Good | Useful as a fallback shape |
| 6 | **Deep link out** | ✅ **High** | ✅ **Very low** | ✅ **High** | 🟡 Fair | ✅ **Built 2026-08-05** |

⚠️ **A correction worth flagging up front:** the obvious-looking path — Homebridge's `eufy-security` plugin, already running on Taylor's Mac mini — is a dead end, and not for a fixable reason. Details in Options 2 and 5.

---

## What I measured on the network [M]

All of the following was run on 2026-08-05 from the Mac mini (192.168.86.55, same /24 as the monitor).

**The device is on the network but does not answer it.**

- The router's DNS resolves `192.168.86.66` → `eufy_baby_camera.lan` (confirmed by reverse lookup against `192.168.86.1`). The IP is correct and the router knows the device.
- Its ARP entry is **`(incomplete)`** on every probe — 10 rounds across roughly four minutes, plus a `/24` sweep of `.60`–`.80`. No ICMP reply, ever.
- The MAC `90:BF:D9:2E:12:F1` never appeared in the ARP table during the sweep.
- UDP probes return `EHOSTUNREACH` — the host cannot even be ARP-resolved.

The camera keeps **no listening presence on the LAN at rest**. It sleeps its radio and wakes when the eufy app or the paired parent unit connects.

**No streaming endpoints reachable — but this is the expected result, not a verdict.**

- TCP connect scan of 35 common ports (including **554**, 8554, 1935, 32100) returned **zero open**, run twice.
- mDNS browse found **no `_rtsp._tcp`, no `_onvif`**, and no eufy service type on the LAN. Notably, even the *supported* eufy IndoorCams here advertise nothing — eufy simply doesn't do service discovery.
- A broadcast probe to `192.168.86.255:32108` (the P2P local-discovery port) drew no replies. The payload was speculative, so this is weak evidence at best.

⚠️ **Read this scan correctly.** It was taken while the camera was asleep *and* before `NAS(RTSP)` had ever been enabled. Both conditions independently guarantee a closed port 554. This establishes *"no listener reachable right now"* — it is **not** evidence against Option 2. The verification protocol below is what actually settles it.

**The eufy Security *account* cannot see the baby monitor.**

Homebridge with `homebridge-eufy-security` already runs on this Mac. Its device cache (`~/.homebridge/eufysecurity/accessories.json`) enumerates everything the eufy Security **API** returns for Taylor's account — 7 devices:

```
T8170T10253051E4   T8170T1025378F22                    (IndoorCam)
T8400P32233505FB   T8400P322335112A   T8400P3223380077
T8400P3223391006   T8400P32233910ED                    (Video Doorbell)
```

`T8354P20251006EC` is **absent**.

⚠️ **Important distinction, easy to get wrong:** this proves the baby monitor is invisible to the eufy Security *HTTP API*. It does **not** prove it's invisible in the eufy Security *app*. Baby devices appear under a separate "Care" tab that the API doesn't expose — which is exactly why the API-based tooling fails while the app-driven RTSP recipe works. Confirmed by the upstream issue thread, where users running `eufy-security-ws` against baby-only accounts see `No stations found. / No devices found.` yet still enable RTSP successfully through the app [V].

**The client library has no concept of this device.** [M]

Installed `eufy-security-client` **v4.0.0-dev.32**:

- `grep -r "T8354"` across the whole `node_modules` tree → **zero hits**.
- `grep -ri "baby"` across `eufy-security-client/build/` → **zero hits**.
- Known model prefixes: `T8023 T8025 T8030 T8110 T8113 T8114 T8122 T8123 T8124 T8130 T8131 T8134 T8140 T8142 T8144 T8150 T8151 T8152 T8153 T8170 T8171 T8172 T8173 T8200 T8202 T8203 T8210 T8213 T8214 T8220 T8221 T8222 T8400 T8401 T8410 T8411 T8414 T8416 T8417 T8419 T8420 T8422 T8423 T8424 T8425 T8426 T8440 T8441 T8442 T8452 T8453 T8500 T8501 T8502 T8503 T8504 T8506 T8510 T8520 T8530`. **No `T83xx` family at all.**
- ⚠️ Trap: `T8150`–`T8153` look like they might be the SpaceView baby monitors, but the code classifies them as `is4GCameraBySn()` — 4G security cameras. Likewise, `E110`/`E210` in the upstream device table are a *smart lock* and a *garage cam*, not baby monitors. Naming collisions abound in this ecosystem.

**The P2P relay path is already unreliable here, for cameras it *does* support.** [M]

From `~/.homebridge/homebridge.log` (window ending 2026-08-05 04:01), on Taylor's own hardware:

| Log signal | Count |
|---|---|
| `Livestream timeout: no P2P stream event within 15s` | 147 |
| `P2P connection failed. Retrying…` | 111 |
| `Livestream failed after N attempts` | 36 |
| `getaddrinfo ENOTFOUND` (cloud auth DNS failure) | 3 |
| `All 3 connection attempts failed. Shutting down plugin` | 1 |

The eufy P2P relay is *already* failing regularly for the IndoorCams and doorbells it fully supports. This is the reliability ceiling any P2P-based design inherits — and a strong argument for preferring RTSP even where both are available.

---

## Option 1 — Deep link to the eufy app

### App identity [V]

Confirmed directly against Apple's lookup API (`https://itunes.apple.com/lookup?id=1424956516`):

| Field | Value |
|---|---|
| Name | **eufy** (formerly "eufy Security"; now the unified app) |
| **Bundle ID** | **`com.security.BatteryCam`** |
| **App Store ID** | **`1424956516`** |
| Seller | Power Mobile Life LLC |
| Minimum iOS | **15.1** |
| Version | 6.0.70 (released 2026-07-30) |
| Category | Lifestyle |

Its own App Store description confirms the consolidation: *"The new all-in-one eufy app … bring together all your favorite eufy products—eufy Security, eufy Clean, eufy Baby, eufy Life, and eufy Pet—into one seamless platform."*

<details>
<summary>Legacy eufy Baby app details (superseded — kept for reference)</summary>

| Field | Value |
|---|---|
| Name | eufy Baby |
| Bundle ID | `com.security.care` |
| App Store ID | `1544694845` |
| Minimum iOS | 12.0 |
| Version | 2.2.4 (2026-07-28) |

Its Android counterpart (`com.oceanwing.care.cam`) registered exactly two schemes, `eufybaby://` and `eufycare://`, both routing only to WebView activities (`/web`, `/explore/web`, `/referral/web`, `/community/web`). No AASA existed for any eufy Baby domain — Apple's CDN returns `Not Found` for both `mybaby.eufylife.com` and `care-app.eufylife.com`.

**Wrong guesses ruled out** [V]: `com.eufylife.smarthome` is the *Android* eufyHome package (iOS is `com.eufylife.EufyHome`); `com.anker.eufybaby` and `com.eufy.baby` don't exist.

</details>

### URL scheme — `eufysecurity://` [V on Android, L on iOS]

Read directly from the unified app's decompiled Android manifest (`com.oceanwing.battery.cam`, target SDK 34, in the TapTrap research dataset). Of **1273 activities, only 7 are exported**, and just one declares a custom scheme:

```xml
<activity name="com.oceanwing.battery.cam.main.DeepLinkSupportActivity" exported="true">
  <intent-filter>
    <action android:name="android.intent.action.VIEW"/>
    <category android:name="android.intent.category.DEFAULT"/>
    <category android:name="android.intent.category.BROWSABLE"/>
    <data android:scheme="eufysecurity" android:host="eufy.com" android:path="/app/support"/>
  </intent-filter>
</activity>
```

Two further exported activities (`ExploreWebviewActivity` → `/explore/web`, `WebOpenSettingActivity` → `/deviceUtil`) declare their scheme via unresolved resource references (`@7F122116`), so their literal value isn't readable from this dataset — but `eufysecurity` is the only custom scheme the app resolves, so they are almost certainly the same [L].

This is **better evidence than we had for the Baby app**: the scheme name is read from a manifest rather than inferred. iOS still needs a `canOpenURL` confirmation [L], but eufy reuses scheme names across platforms, and independent iOS scheme databases list `eufysecurity://` for this app.

### Can we deep link to the camera view? **Still no.** [V]

I checked this specifically for the unified app, since consolidation might have changed it. It hasn't:

```json
{"activity_name": "com.oceanwing.battery.cam.camera.ui.CameraPreviewActivity",
 "is_exported": "false", "intent_filters": []}
```

The live-view activity is **not exported and declares no intent filter** — unreachable from outside the app. The three reachable scheme paths (`/app/support`, `/explore/web`, `/deviceUtil`) are a support page, a marketing WebView, and a device-utility page. None takes a camera identifier.

On iOS the outcome is the same [L]: the scheme opens the app cold, and the user taps through to the camera. Whether the iOS binary hides an undocumented internal router is **[U]** — answering that would mean decrypting the IPA, which is out of scope and against eufy's terms.

### Universal Links exist, but not usefully [V]

Unlike eufy Baby, the unified app **does** have an association file:

```
https://security-app.eufylife.com/.well-known/apple-app-site-association
→ {"applinks":{"details":[{"appID":"BVL93LPC7F.com.security.BatteryCam",
   "paths":["/passport/app_to_app_access/*","/app/*",
            "/smart/external/callbackapp.*","/v1/smart/workwith/alexa/*"]}]}}
```

Corroborated on the Android side, where `AlexaCallbackActivity` and `AuthorizationActivity` both declare `autoVerify="true"` App Links against `security-app.eufylife.com` and `security-smart.eufylife.com`.

But every path is an **OAuth or Alexa account-linking callback** — machinery for connecting third-party services, not content deep links. There is no universal link that opens a camera. So the practical consequence is unchanged: **you must branch manually on `canOpenURL`**, because there's no https link that degrades to the App Store on its own.

### No App Intents, no Siri, no widget [U, strongly negative]

No Siri/Shortcuts/Widget badges on the App Store listing, and the Android manifest declares zero shortcut metadata and zero AppWidget receivers. The **iOS 15.1 minimum deployment target** rules out App Intents (needs 16) and Live Activities (16.1) outright. WidgetKit (14) would now be technically possible — the unified app raised the floor from the Baby app's iOS 12 — but there's no evidence any widget ships. Don't plan around one.

### Ratings

| Dimension | Rating | Why |
|---|---|---|
| Feasibility | ❌ **Blocked** as specified | Launching the app works; deep-linking *to the camera view* does not |
| Complexity | Low (for what's achievable) | One `openURL` call plus a scheme probe |
| Reliability | Medium | Undocumented scheme; eufy could rename it in any release |
| UX | Fair | App switch, cold launch, then a manual tap |

**Verdict:** as scoped, blocked. What remains achievable is Option 6.

---

## Option 2 — Local network streaming 🔬 **The one to investigate**

### The E21 has a native RTSP server [V]

This is the headline finding, and it contradicts what the network scan alone would suggest.

eufy documents RTSP/NAS support across the baby monitor line — [Baby Monitor 2](https://service.eufy.com/article-description/Does-the-Baby-Monitor-2-support-RTSP-NAS) ("supports RTSP/NAS. Video Recordings can be saved to NAS") and the [Baby Monitor 2K Wi-Fi](https://support.nz.eufy.com/support/solutions/articles/154000240261-does-the-baby-monitor-2k-wi-fi-support-rtsp-nas-). There is **no E21-specific support article** — that gap is [U] — but the capability is community-verified on E20/E21 hardware.

I read [bropat/eufy-security-client#634](https://github.com/bropat/eufy-security-client/issues/634) directly. Two independent users, January 2026:

- **@squeaky-nose** (2026-01-20) got it working through Scrypted, then bridged it to HomeKit and watched it in PIP on an Apple TV.
- **@nearha** (2026-01-26): *"Just to confirm that @squeaky-nose RTSP method works — I am using it with Frigate."*

The thread contains raw RTSP wire logs against a baby monitor at `192.168.1.163` showing the camera answering:

```
RTSP/1.0 200 OK
Public: OPTIONS, DESCRIBE, SETUP, TEARDOWN, PLAY, GET_PARAMETER
```

**A real RTSP server runs on the camera.** Before `Continuous recording` was enabled, `DESCRIBE rtsp://192.168.1.163/live0` returned `404 Stream Not Found` — the server is up, but the stream isn't published until the setting is on. That failure mode is worth internalising: *port open, stream 404* is the signature of a half-configured device, not a broken one.

### The recipe [V]

Reproduced verbatim from @squeaky-nose, with the key step emphasised:

1. Open the **unified `eufy` app — NOT the legacy eufy Baby app**. eufy surfaces Baby devices in the main app under a "Care" tab. (The original report predates the rename and says "eufy Security app"; that is the same app.)
2. Select the camera → **Settings → General → Storage → NAS(RTSP)**.
3. Enable the RTSP stream (a few screens of setup).
4. **Under "Video type store to NAS", select "Continuous recording".** ← *"Step 4 is the key to it all — it allowed me to finally get the stream to work for more than 5 minutes."*

Resulting URL:

```
rtsp://<username>:<password>@192.168.86.66:554/live0
```

Port 554, path `/live0`; credentials are set in the app, and auth mode is switchable between Digest and Basic. Corroborated by [iSpyConnect's eufy page](https://www.ispyconnect.com/camera/eufy) (47 eufy models, paths `/live0`–`/live5`, port 554).

**No HomeBase required** [V] — the E21 has none in its architecture. eufy's generic NAS/RTSP article is written around HomeBase, but that applies to HomeBase-paired eufyCams; standalone Wi-Fi cameras serve RTSP from their own IP, which the issue-#634 logs demonstrate. And despite the menu naming, **you do not need an actual NAS** — the Homebridge plugin wiki notes RTSP can generally be activated without one.

### ⚠️ The reliability problem — this is the real risk

eufy cameras **deliberately stop publishing RTSP after a few minutes.** It's a design intent (battery/thermal), not a bug. The [Home Assistant thread on exactly this](https://community.home-assistant.io/t/eufy-camera-rtsp-stream-is-disabled-after-a-few-minutes-my-findings/581001) explicitly names E20/E21 alongside the T8113-Z, and reports:

- **"Continuous recording" is the most promising fix** — one user reported it resolved timeouts *specifically for baby monitors*.
- Switching Digest → Basic auth helped some users, failed for others.
- Others resorted to restarting RTSP every 2–3 minutes programmatically.
- **Multiple 2025–2026 reports say streaming remains unreliable regardless.**

So the honest position: the capability is real and two people have it working, but the failure mode is *"stream silently dies"* — which for a baby monitor is the worst possible failure. **This is why the spike below exists, and why it runs for an hour rather than five minutes.**

### Why the P2P path is a dead end [V/M]

For completeness, since it's the route every existing integration takes. eufy Security devices deliver video over a proprietary **UDP P2P protocol** (CS2 Network "PPPP", *not* TUTK/Kalay), emitting raw H.264/H.265 elementary streams with no container. Bootstrapping requires cloud auth — the `p2p_did`, an expiring DSK key, and the station IP all come from authenticated cloud calls — so there is no offline path.

None of that matters here, because **no P2P client supports the Baby line**: the upstream [supported-devices list](https://github.com/bropat/eufy-security-client/blob/master/docs/supported_devices.md) has no baby monitor of any kind, issue #634 remains **open** (filed 2025-05-03, labelled *need hardware or access*, last activity 2026-01-26), and the local library has zero knowledge of `T8354` [M]. Users running it against baby-only accounts get `No stations found. / No devices found.`

The upstream Home Assistant integration's own maintainers put it plainly: generating the RTSP stream *"is responsibility of hardware and it is very much reliable than P2P based streaming."* Which points the same direction as Taylor's own 147 P2P timeouts.

### ONVIF — no [V]

eufy cameras are not ONVIF-compliant for streaming or PTZ; there's a long-running archived feature request. Some newer firmware may answer WS-Discovery so NVRs can find the camera [L], but you'd still configure RTSP manually. No baby monitor is documented as ONVIF-capable.

### Security history — context only, not a technique [V]

In November 2022, researcher Paul Moore demonstrated that eufy camera streams could be played in VLC via effectively unauthenticated URLs; [The Verge reproduced it](https://www.theverge.com/2022/11/30/23486753/anker-eufy-security-camera-cloud-private-encrypted-authentication) and found the server never validated the token. Anker denied it, then [admitted it in January 2023](https://www.theverge.com/23573362/anker-eufy-security-camera-answers-encryption): streams weren't end-to-end encrypted, and a doorbell uploaded face-setup images to the cloud despite local-storage marketing.

**This is patched and not a viable technique** — the USENIX WOOT '24 paper independently confirms the fixes ~20 months later. It's included as vendor-posture context only.

Two things that *do* remain relevant:

- **[CVE-2023-37822](https://nvd.nist.gov/vuln/detail/cve-2023-37822)**: HomeBase 2 derived its dedicated Wi-Fi WPA2-PSK from the serial number, leaving 24 bits of entropy — brute-forceable in seconds. ⚠️ Scoped correctly: this is **HomeBase 2 only, and the E21 has no HomeBase**, so it does not apply to this device. It's evidence about eufy's engineering standards, not a live risk here.
- **RTSP on the LAN is cleartext.** Basic/Digest auth, unencrypted video. Normal for IP cameras, but it means the nursery feed would be readable by anything on the home network. Worth stating plainly before shipping, and an argument for a strong RTSP password distinct from the eufy account password.

### 🔬 Verification spike — do this before building anything

About 30 minutes, needs Taylor's phone. Every step has a clear pass/fail.

1. **Does the E21 appear in the unified `eufy` app?** Open it (not the legacy Baby app) and look for a "Care" tab. ⚠️ *Homebridge not seeing the device does not predict this* — the app and the API expose different device sets. **If the device isn't there, Option 2 is dead** and Option 6 is the answer.
2. **Enable RTSP:** Settings → General → Storage → NAS(RTSP). Set a strong password. Set **"Video type store to NAS" → "Continuous recording"**. Note the RTSP URL the app shows.
3. **Pin the IP.** Add a DHCP reservation for `90:BF:D9:2E:12:F1` on the Nest router so it stays at `192.168.86.66`.
4. **Confirm the port opens** — run the appendix scan. Expect `554` open. If it's still closed, the setting didn't apply.
5. **Confirm the stream plays:**
   ```bash
   ffprobe -rtsp_transport tcp "rtsp://USER:PASS@192.168.86.66:554/live0"
   ```
   Expect an H.264 stream with resolution and frame rate. A `404 Stream Not Found` means step 2's "Continuous recording" didn't take.
6. **⚠️ The decisive test — soak it for an hour:**
   ```bash
   ffmpeg -rtsp_transport tcp -i "rtsp://USER:PASS@192.168.86.66:554/live0" \
          -t 3600 -f null - 2>&1 | tail -20
   ```
   **This is the whole question.** If it survives 60 minutes without dropping, in-app video is a real project. If it dies after five, Option 2 is dead in practice no matter how good it looks on paper — and Option 6 is the permanent answer.

### If the spike passes: what building it looks like

**`AVPlayer` cannot play RTSP.** That's the central constraint, and it forces a choice:

| Approach | Latency | Complexity | Notes |
|---|---|---|---|
| **MobileVLCKit in-app** | ~1–2s | Medium | Direct RTSP. ⚠️ LGPL/GPL — needs a licensing review before App Store submission |
| **go2rtc on the Mac mini → WebRTC** | **<300ms** | High | Best latency; needs a WebRTC client in-app; adds a Mac-mini dependency |
| **go2rtc → HLS → `AVPlayer`** | 5–15s | **Low** | Trivial to build, but far too laggy for a baby monitor |

The pragmatic pick is **MobileVLCKit** if the licensing clears, since it keeps the Mac mini out of the critical path — a baby monitor that breaks when Homebridge is restarted is not a baby monitor. Otherwise **go2rtc → WebRTC**.

Either way this is LAN-only: it works at home and shows nothing when away, unless you add a VPN (Taylor already has Tailscale on the Mac mini — `100.75.144.60` [M] — which could carry it).

### Ratings

| Dimension | Rating | Why |
|---|---|---|
| Feasibility | 🟡 **Promising, unverified** | RTSP server confirmed on E20/E21 by two users; not yet tested on this unit |
| Complexity | High | RTSP client or relay, plus a video player in a SwiftUI app |
| Reliability | ⚠️ **The open question** | Streams designed to time out; workaround is undocumented and reportedly flaky |
| UX | ✅ Excellent if it works | True in-app video on the sleep card, sub-2s latency, no cloud |

---

## Option 3 — HomeKit

### The E21 has no native HomeKit support [V]

eufy states it directly:

> "Baby monitor devices do not support smart integrations with Alexa/GVA/HomeKit."
> — eufy, [Compatibility Between eufySecurity Devices and Smart Home Devices](https://service.eufy.com/article-description/Compatibility-Between-eufySecurity-Devices-and-Smart-Home-Devices)

Corroborated everywhere: the [E21 product page](https://www.eufy.com/products/e8354121) makes no HomeKit/Matter claim; the [T8354 user guide](https://service.eufy.com/article-description/eufy-Baby-Monitor-E21-User-Guide-T8354) never mentions it; eufy's [HomeKit device list](https://service.eufy.com/article-description/HomeKit-on-eufySecurity-Devices) and [Apple Home Feature Guide](https://service.eufy.com/article-description/Apple-Home-Feature-Guide) omit every baby monitor.

The eufy devices that *do* support HomeKit — eufyCam S3 Pro, eufyCam 2/2 Pro/2C/2C Pro via HomeBase 2, IndoorCam E30, Indoor Cam Pan & Tilt 2K, Indoor Cam 2K, and the E30/E31/C34 locks — include no baby monitors [V]. Nor do the other Baby models: SpaceView E110/E210 are closed RF systems marketed "No App Required", with no Wi-Fi path at all [V].

⚠️ On the "S340 baby" model in the brief: no such product exists. S340 is the eufyCam/SoloCam **S340 security** line.

### But HomeKit is reachable *indirectly* — and the iOS capability is real [V]

Two findings that make this option not-quite-dead:

**1. A relay can synthesise HomeKit support.** This is precisely what @squeaky-nose did in issue #634: RTSP → Scrypted → Scrypted's HomeKit plugin → the camera appears in Apple Home, streamable on an Apple TV. So if Option 2's spike passes, HomeKit becomes available as a *consequence*, without eufy supporting it.

**2. Third-party iOS apps can render HomeKit camera streams.** This is not reserved for Apple's Home app:

- Public API: `HMCameraProfile` → [`HMCameraStreamControl`](https://developer.apple.com/documentation/homekit/hmcamerastreamcontrol) (`startStream()` / `stopStream()`) → the delegate returns an `HMCameraStream`, assigned to [`HMCameraView.cameraSource`](https://developer.apple.com/documentation/homekit/hmcameraview). iOS 10+.
- Existence proof: [HomeCam for HomeKit](https://apps.apple.com/us/app/homecam-for-homekit/id1292995895) has shipped third-party live HomeKit streaming for years.
- Entitlement is the plain, self-serve `com.apple.developer.homekit` plus `NSHomeKitUsageDescription`. No special approval, no known review obstacle.

**Caveats** [V]:

1. **HomeKit does not work in the iOS Simulator** — a physical device is required. That's a real drag on a codebase whose tests currently run happily on the simulator (`make test`).
2. `HMCameraView` is UIKit, so SwiftUI needs a `UIViewRepresentable` wrapper.
3. Thinly documented — Apple's own forum thread on this exact flow ([#766087](https://developer.apple.com/forums/thread/766087)) sat unanswered.

**Would I route through HomeKit if the spike passes?** Probably not. RTSP → Scrypted → HomeKit → `HMCameraStreamControl` is three hops and two daemons to display a stream Two of Us could consume directly with MobileVLCKit. It's a reasonable *fallback shape* if direct RTSP proves awkward in-app, and it has the side benefit of putting the camera on every Apple TV and iPad in the house — but it isn't the short path.

### Ratings

| Dimension | Rating | Why |
|---|---|---|
| Feasibility | ❌ Direct: blocked · 🟡 Via relay: possible | No native support; Scrypted can synthesise it if Option 2 works |
| Complexity | Medium | Public API, but UIKit bridging, device-only testing, plus a relay |
| Reliability | Would be good | First-party framework — though it inherits Option 2's stream risk |
| UX | Excellent | Native video; bonus: camera appears on Apple TV and iPad too |

---

## Option 4 — eufy API / cloud streaming

### There is no official API [V]

No developer portal, no public API docs, no camera SDK. eufy's only "partner program" is a reseller arrangement. Community requests go back years with no delivery.

A misconception worth correcting: **eufy Clean has no official API either.** Every eufy vacuum integration is reverse-engineered off *Tuya's* protocol, because eufy vacuums are Tuya-OEM hardware. Cameras aren't Tuya-based, so even that accidental door doesn't exist here.

### No cloud stream URL [V]

`eufy-security-client`'s feature list historically mentioned an RTMP-over-cloud path; the README now records it as **outdated, non-functional, and removed**. All working video is the proprietary P2P protocol. There is no cloud endpoint returning an HLS or RTMP URL.

### The unofficial stack is being actively retired [V]

`eufy-security-client` carries an explicit deprecation notice: eufy is migrating to a unified **"eufy Mega"** backend, and per the maintainer, eufy *"has already started removing access to the legacy APIs."* Push notifications were restored against the new backend only as a stopgap. Building on this today means building on something with a publicly announced expiry date — for a device family it doesn't support anyway.

### Terms of service [V]

eufy's [Terms of Service](https://www.eufy.com/policies/terms-of-service) §8.2(6) prohibits users to:

> "reverse engineer, decompile, or otherwise attempt to extract the source code"

§8.2(4) separately forbids circumventing authentication. Using your own credentials against your own devices is the mildest version of this, and many Homebridge/HA users do it — but it is a plain ToS violation, and eufy can terminate the account Taylor's wife depends on for the actual monitor.

**Worth noting the contrast:** Option 2 involves *no* ToS problem. Enabling RTSP is a documented, first-party setting in eufy's own app. That asymmetry is a real point in Option 2's favour.

### Practical risks, documented [V]

From the Homebridge plugin's Common Issues wiki: captcha walls (eufy flags accounts for 24 hours), 2FA prompts that block the client, and session conflicts with the real app. The community's standard mitigation is telling — create a **second eufy account with 2FA disabled**.

That's a meaningful security downgrade on an account with a live view into a baby's room. **That tradeoff alone argues against this path even if the device were supported.** No confirmed hard-ban reports were found [U]; the realistic failure mode is nuisance-grade churn.

### Ratings

| Dimension | Rating | Why |
|---|---|---|
| Feasibility | ❌ **Blocked** | No API; Baby line unsupported; no cloud stream URL |
| Complexity | Very high | Undocumented backend, captcha/2FA handling, token churn |
| Reliability | Very low | Legacy backend being switched off by the vendor |
| UX | Poor even if built | Captcha and 2FA interruptions landing on a parent at 3am |

---

## Option 5 — Homebridge / Scrypted relay

The answer splits cleanly depending on what the relay is fed.

### ❌ Via the eufy plugin (P2P): dead, twice over

**It cannot see the device** [M]. `homebridge-eufy-security` delegates all device support to `eufy-security-client`, which has no knowledge of `T8354`. Confirmed from the other end too: the plugin's device cache enumerates 7 devices from Taylor's account and the baby monitor isn't among them.

**And it's already unreliable for devices it does support** [M]: 147 livestream timeouts, 111 P2P connection failures, 36 outright failures, one full plugin shutdown — on Taylor's own hardware. The upstream wiki independently documents the same class of problems, plus a hard limit of **one camera per HomeBase streaming at a time**.

### 🟡 Via RTSP: viable, and demonstrated

This is the shape @squeaky-nose actually shipped — and note it uses **Scrypted, not Homebridge**, with the eufy plugin entirely out of the picture:

```
E21 camera  ──RTSP/554──▶  Scrypted (RTSP Camera device)
                                │
                                ├─▶ HomeKit plugin ──▶ Apple Home / Apple TV
                                └─▶ WebRTC / HLS ────▶ Two of Us
```

Scrypted is the better relay here on the merits: faster streams than Homebridge, native RTSP/WebRTC/HLS output, and it treats the E21 as a generic RTSP camera — no eufy-specific support required, which is exactly why it works. ⚠️ Do **not** reach for Scrypted's *eufy* plugin: its author publicly abandoned eufy support, and the community plugin that exists inherits the same Security-only device scope. The generic **RTSP Camera** device type is the one that matters.

**The tradeoff to weigh:** a relay adds a Mac-mini dependency to the critical path. A baby monitor that goes dark because Homebridge restarted at 2am is worse than no in-app video at all. Direct MobileVLCKit → RTSP from the app avoids that entirely. The relay earns its keep only if you want the camera in Apple Home too, or if go2rtc's sub-300ms WebRTC is worth the coupling.

### Ratings

| Dimension | Rating | Why |
|---|---|---|
| Feasibility | ❌ P2P plugin · 🟡 RTSP via Scrypted | Demonstrated working by a user on E21 hardware |
| Complexity | Medium | Scrypted setup is straightforward; WebRTC client in-app is not |
| Reliability | Inherits Option 2's risk, plus a Mac-mini dependency | Two things to fail instead of one |
| UX | Good | Adds Apple TV / iPad viewing as a bonus |

---

## Option 6 — Simple deep link ✅ **Built**

A camera button on the sleep card that opens the unified `eufy` app. No video inside Two of Us; one tap to get to it.

Mechanically identical to Option 1 — the difference is scoping it to what actually works: **launch the app, land on its device list, parent taps the camera.** One extra tap versus a true deep link, achievable today, with no dependency on anything undocumented staying put.

### Why ship it regardless of the spike

- **It always works.** Falls back cleanly to the App Store when the app is absent.
- **Zero risk.** No cloud auth, no second eufy account, no 2FA downgrade, no ToS exposure.
- **It stays useful even if Option 2 succeeds.** In-app RTSP is LAN-only; the deep link is the natural away-from-home path, since the eufy app handles remote viewing properly.
- **It points at the app that's actually being invested in.** Targeting the unified app rather than the legacy Baby app means the button doesn't rot as consolidation proceeds — and it's the same app the parent must already use to enable RTSP for Option 2.
- **Cheap to remove** if it stops earning its place.

### ✅ Built — 2026-08-05

Shipped as [BabyCamLink.swift](../TwoOfUs/Features/Sleep/BabyCamLink.swift) plus a corner button on [SleepActiveCard.swift](../TwoOfUs/Features/Sleep/SleepActiveCard.swift), covered by [BabyCamLinkTests.swift](../TwoOfUsTests/BabyCamLinkTests.swift).

**Gated on SNOO sessions only** (`sleep.isFromSnoo`). The camera points at the bassinet, so a contact nap or a stroller sleep would link to an empty crib.

**Placement:** a `video.circle.fill` badge in the card's top-right corner, matching the position, size, and palette rendering of the log tiles' plus badges. The glyph is 26pt but the button carries a 44pt frame and an explicit `contentShape`, so the tap target meets the accessibility minimum rather than matching the artwork.

Three things that mattered in the build:

1. **`LSApplicationQueriesSchemes` is required** — added to `project.yml`. `canOpenURL` returns `false` with no error for unlisted schemes, so without it every tap would have silently detoured to the App Store.
2. **The App Store URL must keep its canonical slug.** The first attempt used the slugless `…/us/app/id1424956516`, which returns 200 to `curl` but is a **301 redirect** — and iOS matches universal links against the App Store's association file *before* making any request. Tapping it in the simulator produced "Safari cannot open the page because the address is invalid"; the canonical `…/us/app/eufy/id1424956516` is recognized as an App Store link. Reproduced with `simctl openurl` alone, so it's not app-side.
3. **Probe order is deliberate.** `eufysecurity://` first, so a parent with both apps installed lands in the one eufy is still developing; the two legacy Baby schemes trail it for a phone that hasn't migrated. Delete them once both phones have.

⚠️ **Still unverified: the iOS scheme.** `eufysecurity://` is read from the Android manifest and inferred for iOS [L]. The simulator can't install the eufy app, so this needs one tap on a real phone — if the button opens the App Store instead of eufy, the scheme name is wrong.

Because the only Universal Links are OAuth callbacks, the fallback is an explicit `canOpenURL` branch rather than an https link that degrades on its own.

A settings toggle, if it's ever wanted, belongs in [IntegrationsSettingsView.swift](../TwoOfUs/Features/Settings/IntegrationsSettingsView.swift), whose doc comment already anticipates it: *"SNOO today, with room for future integrations."*

### Ratings

| Dimension | Rating | Why |
|---|---|---|
| Feasibility | ✅ **High** | Plain `openURL`; App Store fallback always available |
| Complexity | ✅ **Very low** | One helper, one button, one Info.plist key — a few hours |
| Reliability | ✅ **High** | Worst case degrades to an App Store link, never a crash |
| UX | 🟡 **Fair** | App switch + cold launch + one tap; no in-app video |

---

## Recommended sequence

1. ~~**Now — build Option 6.**~~ ✅ **Done 2026-08-05** — corner camera button on the SNOO sleep card, `LSApplicationQueriesSchemes` wired, tests green. One step outstanding: confirm `eufysecurity://` resolves on a real phone.
2. **Next — run the Option 2 spike.** ~30 minutes with the phone. The one-hour `ffmpeg` soak is the decisive test; everything before it is setup.
3. **If the soak passes** — build in-app RTSP with MobileVLCKit (pending a licence review) or go2rtc → WebRTC. Keep Option 6 as the away-from-home path.
4. **If the soak fails** — stop. Option 6 is the answer, and the cheapest route to real in-app video becomes *different hardware*: a HomeKit or plain-RTSP camera in the nursery makes Option 3 immediately viable with no vendor games at all.

## What would change this answer

- **The spike passing.** That's the live question; everything else is settled.
- **A HomeKit camera in the nursery.** An IndoorCam E30 or any HomeKit-certified camera makes Option 3 work directly — public API, no cloud scraping, excellent UX.
- **Any camera with plain RTSP** that doesn't self-disable. Feed it through go2rtc for sub-second WebRTC. Well-trodden ground.
- **[Issue #634](https://github.com/bropat/eufy-security-client/issues/634) being implemented.** Unlikely — labelled *need hardware or access*, and the library is being retired by the eufy Mega migration. Not worth waiting on.
- **eufy shipping HomeKit or Matter on the Baby line.** No evidence on any roadmap [U].

## Appendix — repeatable port scan

Run this **while the `eufy` app has a live view open** (the camera sleeps otherwise), and again after enabling `NAS(RTSP)`:

```bash
python3 - <<'PY'
import socket, concurrent.futures as cf
HOST = "192.168.86.66"
PORTS = [21,22,23,53,80,81,443,554,853,1883,1935,3702,5000,8000,8001,8080,8081,
         8083,8443,8554,8555,8600,8800,8888,8899,9000,9999,10000,32100,34567,
         37777,49152,50000]
def probe(p):
    s = socket.socket(); s.settimeout(1.5)
    try: s.connect((HOST, p)); return p
    except Exception: return None
    finally: s.close()
with cf.ThreadPoolExecutor(40) as ex:
    print("open:", [p for p in ex.map(probe, PORTS) if p] or "none")
PY
```

Expected before enabling RTSP: `none`. Expected after: `554`.

---

## Sources

**Verified locally (2026-08-05)** — `~/.homebridge/config.json`, `~/.homebridge/eufysecurity/accessories.json`, `~/.homebridge/homebridge.log`, `eufy-security-client` v4.0.0-dev.32 build output, plus the network scans described above.

**The decisive thread**
- [bropat/eufy-security-client#634 — "Add support for Eufy Baby Monitor E20/E21"](https://github.com/bropat/eufy-security-client/issues/634) — the RTSP recipe, raw wire logs, and two independent confirmations
- [Home Assistant — "Eufy camera RTSP stream is disabled after a few minutes (my findings)"](https://community.home-assistant.io/t/eufy-camera-rtsp-stream-is-disabled-after-a-few-minutes-my-findings/581001)
- [iSpyConnect — eufy RTSP paths and ports](https://www.ispyconnect.com/camera/eufy)

**Apple**
- [iTunes Lookup API — id1424956516](https://itunes.apple.com/lookup?id=1424956516) · [eufy (unified app) on the App Store](https://apps.apple.com/us/app/id1424956516) · [Introduction to New eufy App](https://service.eufy.com/article-description/Introduction-to-New-eufy-App)
- Legacy, superseded: [iTunes Lookup API — id1544694845](https://itunes.apple.com/lookup?id=1544694845) · [eufy Baby on the App Store](https://apps.apple.com/us/app/eufy-baby/id1544694845)
- [`HMCameraStreamControl`](https://developer.apple.com/documentation/homekit/hmcamerastreamcontrol) · [`HMCameraView`](https://developer.apple.com/documentation/homekit/hmcameraview) · [Developer forum #766087](https://developer.apple.com/forums/thread/766087)
- [HomeCam for HomeKit](https://apps.apple.com/us/app/homecam-for-homekit/id1292995895) (third-party HomeKit streaming existence proof)

**eufy official**
- [Baby Monitor E21 product page](https://www.eufy.com/products/e8354121) · [E21 User Guide (T8354)](https://service.eufy.com/article-description/eufy-Baby-Monitor-E21-User-Guide-T8354)
- [Does the Baby Monitor 2 support RTSP/NAS](https://service.eufy.com/article-description/Does-the-Baby-Monitor-2-support-RTSP-NAS) · [Baby Monitor 2K Wi-Fi RTSP/NAS](https://support.nz.eufy.com/support/solutions/articles/154000240261-does-the-baby-monitor-2k-wi-fi-support-rtsp-nas-) · [About NAS/RTSP](https://service.eufy.com/article-description/About-NAS-RTSP)
- [Compatibility with Smart Home Devices](https://service.eufy.com/article-description/Compatibility-Between-eufySecurity-Devices-and-Smart-Home-Devices) · [HomeKit on eufySecurity Devices](https://service.eufy.com/article-description/HomeKit-on-eufySecurity-Devices) · [Apple Home Feature Guide](https://service.eufy.com/article-description/Apple-Home-Feature-Guide)
- [Terms of Service](https://www.eufy.com/policies/terms-of-service)

**Community / reverse engineering**
- [bropat/eufy-security-client](https://github.com/bropat/eufy-security-client) · [supported devices](https://github.com/bropat/eufy-security-client/blob/master/docs/supported_devices.md)
- [homebridge-eufy-security](https://github.com/homebridge-plugins/homebridge-eufy-security) · [Streaming Settings wiki](https://github.com/homebridge-eufy-security/plugin/wiki/Streaming-Settings) · [Common Issues wiki](https://github.com/homebridge-eufy-security/plugin/wiki/Common-Issues)
- [fuatakgun/eufy_security (Home Assistant)](https://github.com/fuatakgun/eufy_security) · [go2rtc](https://go2rtc.com/) · [Scrypted](https://www.scrypted.app/) · [koush/scrypted eufy discussion](https://github.com/koush/scrypted/discussions/627)
- [beerphilipp/taptrap — `com.oceanwing.care.cam` manifest analysis](https://github.com/beerphilipp/taptrap) · [adysec/h1_asset — eufy iOS bundle IDs](https://github.com/adysec/h1_asset)
- [PPPP protocol overview (palant.info)](https://palant.info/2025/11/05/an-overview-of-the-pppp-protocol-for-iot-cameras/) · Goeman et al., ["Reverse Engineering the Eufy Ecosystem"](https://www.usenix.org/system/files/woot24-goeman.pdf), USENIX WOOT '24
- [The Verge — eufy encryption claims (2022)](https://www.theverge.com/2022/11/30/23486753/anker-eufy-security-camera-cloud-private-encrypted-authentication) · [The Verge — Anker admits (2023)](https://www.theverge.com/23573362/anker-eufy-security-camera-answers-encryption) · [CVE-2023-37822](https://nvd.nist.gov/vuln/detail/cve-2023-37822)
