# Xcode Cloud setup

CI/CD for Two of Us: every push to `main` archives the app on Apple's runners and
uploads it to TestFlight, where both internal testers (the two of us) get it
automatically.

## What the repo already handles

- **Generated project.** `TwoOfUs.xcodeproj` is gitignored (XcodeGen owns it), so
  Xcode Cloud's clone has no project file. `ci_scripts/ci_post_clone.sh` runs
  right after clone, installs XcodeGen via Homebrew, and runs `xcodegen generate`
  before Xcode Cloud resolves the project. This is Apple's documented pattern for
  XcodeGen/Tuist repos.
- **Build numbers.** The same script stamps Xcode Cloud's `CI_BUILD_NUMBER` into
  `CURRENT_PROJECT_VERSION`, so every upload has a unique, increasing
  `CFBundleVersion` — no manual bumps, no "build already exists" upload failures.
  `MARKETING_VERSION` (the user-facing 0.1.0) stays manual in `project.yml`.
- **Signing.** `CODE_SIGN_STYLE: Automatic` + `DEVELOPMENT_TEAM: Q58H65DQ64` are
  set in `project.yml`. Xcode Cloud uses its own cloud-managed certificates and
  profiles for the archive — nothing to upload or renew.
- **Shared scheme.** XcodeGen generates the `TwoOfUs` scheme as shared
  (`xcshareddata`), which Xcode Cloud requires.
- **Export compliance.** `ITSAppUsesNonExemptEncryption: NO` is in the Info.plist,
  so TestFlight builds don't wait on the manual compliance question.
- **push entitlement.** `aps-environment` is `development` in the entitlements
  file; Xcode's distribution signing flips it to `production` automatically.

## One-time setup (interactive, ~15 minutes)

Prereqs: paid Apple Developer Program membership on team `Q58H65DQ64`, and
admin access to the `tseale/two-of-us` GitHub repo.

### 1. Create the app record in App Store Connect

Xcode Cloud attaches to an app record (TestFlight needs one anyway).

1. [App Store Connect](https://appstoreconnect.apple.com) → **Apps** → **+** → **New App**.
2. Platform **iOS**, name **Two of Us** (pick a fallback if taken — TestFlight-only,
   so the public name barely matters), bundle ID **com.taylorseale.twoofus**,
   any SKU (e.g. `twoofus`).
   - If the bundle ID isn't offered, register it first at
     [developer.apple.com → Identifiers](https://developer.apple.com/account/resources/identifiers/list)
     with the iCloud, App Groups, and Push Notifications capabilities. (If you've
     already run the app on a device from Xcode with automatic signing, it likely
     exists.) The widget bundle ID (`…twoofus.widgets`) doesn't need its own record.

### 2. Create the workflow in Xcode

1. `make project && open TwoOfUs.xcodeproj` (workflow creation needs the project
   open locally).
2. Menu **Integrate → Create Workflow…** (or Report navigator → Cloud tab).
   Select the **TwoOfUs** app, sign in with your Apple ID if prompted.
3. Xcode walks you through:
   - **Grant access to the repo** — it sends you to GitHub to install the
     **Xcode Cloud** GitHub App on `tseale/two-of-us`. Grant access to just
     that repo.
   - **Confirm the app** in App Store Connect (the record from step 1).
4. Edit the default workflow before saving:
   - **Environment**: latest released Xcode (must be ≥ 26 for the iOS 26
     deployment target); macOS latest.
   - **Start Conditions**: Branch Changes → `main`.
   - **Actions**: a single **Archive — iOS** action, scheme `TwoOfUs`,
     deployment preparation **TestFlight (Internal Testing Only)**.
     Remove any Build/Test actions the template added — there's no test target yet.
   - **Post-Actions**: **TestFlight Internal Testing** → create/pick an internal
     group (e.g. "Parents") containing both Apple IDs.
5. Save, then **Start Build** to kick off build #1 manually. First build takes
   ~15–20 min (clean runners; `brew install xcodegen` adds a minute or so).

### 2b. The "App Store Release" workflow (added 2026-07-14)

The Default workflow's **TestFlight (Internal Testing Only)** distribution
produces builds with `buildAudienceType: INTERNAL_ONLY` — App Store Connect
silently disables them in the version page's *Add Build* dialog; they can
never be submitted to the App Store. A second workflow exists for releases
(created via ASC web → Xcode Cloud → Manage Workflows → Duplicate):

- **Name**: App Store Release
- **Start Conditions**: *Manual Start* (any branch) + *Tag Changes* for tags
  **beginning with `v`**
- **Action**: Archive — iOS, scheme TwoOfUs, deployment preparation
  **App Store Connect** (these builds still reach internal TestFlight too)
- **Post-Actions**: none

**Release convention:** bake the build on TestFlight via normal `main`
pushes, then tag that exact commit and push the tag:

```sh
git tag v1.0.1 && git push origin v1.0.1
```

The tag build is the only App-Store-eligible artifact. Keep
`MARKETING_VERSION` in `project.yml` equal to the tag (minus the `v`) so the
tag, the ASC version record, and the binary agree. Then in ASC: version page
→ Add Build → pick it → Save → Add for Review.

### 3. Install on phones

Both testers: accept the TestFlight email invite, install the TestFlight app,
install Two of Us. Every later green build on `main` lands in TestFlight
automatically — internal-group builds need no Beta App Review.

## Day-to-day

- Merge to `main` → Xcode Cloud archives → TestFlight pushes the build to both
  phones. Nothing manual.
- Monitor builds in Xcode's Report navigator (Cloud tab) or App Store Connect →
  Apps → Two of Us → **Xcode Cloud**.
- Bump `MARKETING_VERSION` in `project.yml` when you want a new user-facing
  version; build numbers take care of themselves.
- Free tier is 25 compute-hours/month — plenty at ~15 min per build.

## Troubleshooting

- **"No Xcode project found" at workflow creation** — the workflow editor wants
  the locally generated project open; run `make project` first. On the runner
  itself, `ci_post_clone.sh` handles generation.
- **Signing errors on the runner** — confirm the bundle ID exists under team
  `Q58H65DQ64` with iCloud/App Groups/Push capabilities, and that the workflow's
  Archive action uses TestFlight deployment preparation (that's what enables
  cloud signing).
- **"Exporting for App Store Distribution failed → Code Signing"** after adding a
  **new extension/target** — cloud signing auto-registers the new bundle id but
  does *not* reliably enable special capabilities on it. Every new signable
  target's bundle id must exist as an App ID under `Q58H65DQ64` with its
  capabilities turned on *before* the archive can export. This bit Builds 47–49:
  the new `com.taylorseale.twoofus.notificationcontent` content extension needs
  the **App Groups** capability + `group.com.taylorseale.twoofus` assigned. See
  `docs/NOTIFICATIONS.md` → "Notification-content-extension App ID" for the
  step-by-step. Rule of thumb: any time you add a target with an entitlement,
  register its App ID + capability in the portal in the same change.
- **CloudKit**: TestFlight builds use the *production* CloudKit container
  environment. Deploy the schema (CloudKit Console → Deploy Schema Changes to
  Production) before relying on sync in TestFlight builds — see the dev-vs-prod
  notes in memory/docs.
