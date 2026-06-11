# TestFlight feedback → autofix pipeline

When a beta tester (one of the two of us) submits feedback or hits a crash in
TestFlight, this pipeline turns it into a reviewed fix with no manual triage:

```
TestFlight feedback / crash
        │  (App Store Connect API, polled hourly)
        ▼
GitHub issue, labeled `testflight-feedback`     ← .github/workflows/testflight-feedback.yml
        │  (label event)                          + scripts/testflight_feedback_to_issues.py
        ▼
Claude: triage → analyze → plan → implement     ← .github/workflows/testflight-autofix.yml
        │
        ▼
Draft PR ("Fixes #N") — YOU review and merge
        │
        ▼
Merge to main → Xcode Cloud → new TestFlight build (docs/XCODE_CLOUD.md)
```

The human gate is the PR. Nothing reaches `main` (and therefore TestFlight)
without your review. If Claude judges feedback non-actionable (praise, feature
ideas, things it can't localize in code), it labels the issue `needs-human`
with its triage reasoning instead of opening a PR.

## One-time setup

### 1. App Store Connect API key

The poller reads feedback via Apple's official beta-feedback endpoints (added
in the WWDC 2025 ASC API update).

1. [App Store Connect](https://appstoreconnect.apple.com) → **Users and
   Access** → **Integrations** → **App Store Connect API** → **Team Keys** →
   **+**.
2. Role: **App Manager** (Admin also works; lower roles are unverified for the
   feedback endpoints).
3. Download the `.p8` file — Apple lets you download it **once**. Note the
   **Key ID** (on the key row) and the **Issuer ID** (top of the page).

### 2. GitHub repo secrets

Repo → **Settings → Secrets and variables → Actions**, add:

| Secret | Value |
| --- | --- |
| `ASC_ISSUER_ID` | Issuer ID from the API Keys page |
| `ASC_KEY_ID` | Key ID of the key you created |
| `ASC_PRIVATE_KEY` | Full contents of the `.p8` file (including BEGIN/END lines) |
| `ASC_APP_ID` | Numeric Apple ID of the app (App Store Connect → app → App Information). Optional — resolved from the bundle ID if unset |
| `TESTFLIGHT_ISSUES_TOKEN` | Fine-grained PAT, see below |
| `ANTHROPIC_API_KEY` | API key from [console.anthropic.com](https://console.anthropic.com) |

**Why a PAT and not the built-in `GITHUB_TOKEN`?** GitHub deliberately
suppresses workflow triggers for events created with a workflow's own default
token (to prevent runaway loops). If the poller filed issues with
`GITHUB_TOKEN`, the `labeled` event would never start the autofix workflow.
Create a **fine-grained PAT** (GitHub → Settings → Developer settings →
Fine-grained tokens) scoped to **only `tseale/two-of-us`** with repository
permission **Issues: Read and write**, set a long expiry, and store it as
`TESTFLIGHT_ISSUES_TOKEN`.

### 3. Labels (automatic)

The poller creates the `testflight-feedback` label on first run. Claude
creates `needs-human` when it first triages something non-actionable. Nothing
to do manually.

## Day-to-day

- Submit feedback from TestFlight (screenshot → markup → share beta feedback,
  or the crash dialog). Within ~an hour an issue appears; minutes later either
  a draft PR (linked from the issue) or a `needs-human` triage comment.
- Review the PR — it includes root-cause analysis and an on-device manual test
  script. Run it on your phone if warranted, then merge. Xcode Cloud ships it.
- **Retry / manual trigger:** remove and re-add the `testflight-feedback`
  label on an issue to re-run Claude on it. You can also write your own issue
  describing a bug and add the label — the pipeline doesn't care where the
  issue came from.
- **Force a poll now:** Actions → "TestFlight feedback → issues" → Run
  workflow.

## Costs and limits

- Hourly poll is free-tier GitHub Actions territory (~1 min/run).
- Each autofix run is an Anthropic API spend; `--max-turns 60` caps runaway
  sessions. With 2 trusted testers volume is effectively zero unless something
  is actually broken.
- ASC API: the poller fetches the newest 200 submissions per type per run —
  far beyond what 2 testers produce.

## Known limitations

- **No build verification.** Actions runners are Linux; the Swift code can't
  be compiled there, so Claude's fixes are reviewed-but-unbuilt until you open
  the PR branch locally (`make project`) or merge and watch Xcode Cloud. If a
  fix breaks the build, Xcode Cloud fails before anything reaches TestFlight.
- **Screenshot URLs expire.** Apple's feedback screenshot links die after a
  short window; the originals stay in App Store Connect → TestFlight →
  Feedback. Claude also can't see the images — it works from the tester
  comment and metadata, so write a sentence with your screenshots.
- **Crash symbolication.** Crash logs come from Apple as `logText`; if frames
  show as addresses, grab the symbolicated log from the Xcode Organizer
  instead and paste it into the issue.
- **Prompt injection surface.** Issue text is fed to Claude with write access
  to branches. Fine while the only testers are the two of you; revisit before
  ever widening the beta group.

## Troubleshooting

- **Issues appear but Claude never runs** → the poller is using the default
  token; check `TESTFLIGHT_ISSUES_TOKEN` exists and hasn't expired (the
  workflow fails loudly if it's unset, but an expired PAT returns 401s).
- **401 from App Store Connect** → key revoked, or `ASC_PRIVATE_KEY` missing
  its BEGIN/END lines, or Issuer/Key ID mismatch.
- **`No App Store Connect app found`** → set `ASC_APP_ID` explicitly; the
  bundle-ID lookup requires the app record to exist (docs/XCODE_CLOUD.md §1).
- **Duplicate issues** → the dedupe marker (`<!-- testflight-feedback-id: … -->`)
  was edited out of an issue body; leave the hidden comment intact.
