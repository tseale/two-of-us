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

## Automating the one-time setup (Claude on a Mac with computer use)

This section is a runbook for an agent. If you are Claude running locally with
browser/computer-use access, follow it exactly; if you are the human, you can
follow it too — it's just unusually explicit.

### Ground rules for the agent

- **Never handle the human's credentials.** At any password, passkey, 2FA, or
  CAPTCHA prompt — Apple or GitHub — stop and hand control to the human, then
  resume after they're signed in. Do not ask for credentials in chat.
- **Keep secret values out of the transcript and out of screenshots.** When a
  page reveals a token, copy it to the clipboard in the browser, then shell out
  with `pbpaste` so the value never appears as text you read or type:
  `pbpaste | gh secret set NAME --repo tseale/two-of-us`, then clear it with
  `pbcopy < /dev/null`.
- **Prefer the CLI.** Only two steps below need the browser (ASC key, PAT);
  GitHub has no API for either. Everything else is `gh`/`python3`.
- **Verify every step before the next one.** Each step ends with a check
  command. If it fails, fix that step — don't continue.
- **Be idempotent.** Run `gh secret list --repo tseale/two-of-us` first and
  skip secrets that already exist. Never create a second ASC key or PAT if one
  exists — `.p8` files and PATs are shown once and can't be re-downloaded, so a
  duplicate is just a dangling credential. If a key exists but its secret
  doesn't, stop and ask the human.

### Prerequisites (human, ~2 min)

- `brew install gh` and `gh auth login` completed — agent verifies with
  `gh auth status`.
- Browser profile signed in (or ready to sign in) to appstoreconnect.apple.com
  (account needs the **Admin** role to create API keys) and github.com.
- macOS Screen Recording + Accessibility permissions granted to the
  computer-use tooling.

### Step 1 — App Store Connect API key (browser)

1. Open <https://appstoreconnect.apple.com/access/integrations/api> →
   **Team Keys** tab. (Hand off for sign-in/2FA if prompted.)
2. Copy the **Issuer ID** shown at the top of the page.
3. **+** to add a key: name `testflight-feedback-automation`, role
   **App Manager** → Generate.
4. From the new key's row, note the **Key ID** and click **Download** (allowed
   once; lands at `~/Downloads/AuthKey_<KEYID>.p8`).
5. Set the three secrets and clean up:

   ```sh
   gh secret set ASC_ISSUER_ID  --repo tseale/two-of-us --body "<issuer-id>"
   gh secret set ASC_KEY_ID     --repo tseale/two-of-us --body "<key-id>"
   gh secret set ASC_PRIVATE_KEY --repo tseale/two-of-us < ~/Downloads/AuthKey_<KEYID>.p8
   ```

   Then ask the human whether to archive the `.p8` in their password manager
   or delete it (`rm ~/Downloads/AuthKey_<KEYID>.p8`). Issuer ID and Key ID
   are identifiers, not secrets — they may appear in the transcript.

**Verify** (also captures the numeric app ID):

```sh
pip3 install --quiet "pyjwt[crypto]" requests
ASC_ISSUER_ID=… ASC_KEY_ID=… ASC_PRIVATE_KEY="$(cat ~/Downloads/AuthKey_<KEYID>.p8)" \
python3 -c "
import os, time, jwt, requests
t = jwt.encode({'iss': os.environ['ASC_ISSUER_ID'], 'iat': int(time.time()),
                'exp': int(time.time())+600, 'aud': 'appstoreconnect-v1'},
               os.environ['ASC_PRIVATE_KEY'], algorithm='ES256',
               headers={'kid': os.environ['ASC_KEY_ID']})
r = requests.get('https://api.appstoreconnect.apple.com/v1/apps',
                 params={'filter[bundleId]': 'com.taylorseale.twoofus'},
                 headers={'Authorization': f'Bearer {t}'})
r.raise_for_status()
print('App ID:', r.json()['data'][0]['id'])
"
```

A printed App ID means auth works end to end; store it:
`gh secret set ASC_APP_ID --repo tseale/two-of-us --body "<app-id>"`.
(401 → key IDs/p8 mismatch; empty `data` → app record missing, see
docs/XCODE_CLOUD.md §1.)

### Step 2 — fine-grained PAT (browser)

1. Open <https://github.com/settings/personal-access-tokens/new>. (Hand off if
   GitHub asks to re-confirm the password — sudo mode.)
2. Fields: name `testflight-issues-bot`; expiration **1 year** (the max);
   resource owner `tseale`; **Only select repositories** → `tseale/two-of-us`;
   Repository permissions → **Issues: Read and write** (Metadata: read is
   added automatically). Generate token.
3. The token is shown once. Click its copy button, then immediately:

   ```sh
   pbpaste | gh secret set TESTFLIGHT_ISSUES_TOKEN --repo tseale/two-of-us
   pbcopy < /dev/null
   ```

4. Remind the human: this PAT expires in a year, at which point the poller
   starts failing with 401s — recreate and re-set the secret.

### Step 3 — Anthropic API key

No API for key creation. Ask the human to create/copy a key at
<https://console.anthropic.com> (hand off — billing credentials), copy it,
then: `pbpaste | gh secret set ANTHROPIC_API_KEY --repo tseale/two-of-us` and
clear the clipboard.

**Verify all secrets exist:** `gh secret list --repo tseale/two-of-us` shows
`ASC_ISSUER_ID`, `ASC_KEY_ID`, `ASC_PRIVATE_KEY`, `ASC_APP_ID`,
`TESTFLIGHT_ISSUES_TOKEN`, `ANTHROPIC_API_KEY`.

### Step 4 — end-to-end smoke test (CLI only)

```sh
# Poller runs cleanly against the real ASC API (files issues only if real feedback exists)
gh workflow run "TestFlight feedback → issues" --repo tseale/two-of-us
gh run watch --repo tseale/two-of-us --exit-status

# Exercise the autofix path with a synthetic, obviously-toy report
gh label create testflight-feedback --repo tseale/two-of-us \
  --color 1E6FEB --description "Auto-filed from TestFlight beta feedback" || true
gh issue create --repo tseale/two-of-us \
  --title "[TestFlight feedback] smoke test: please triage as non-actionable" \
  --body "Pipeline smoke test, not real feedback. Expected outcome: label this needs-human and comment; do not open a PR." \
  --label testflight-feedback
```

Issues created with the human's own `gh` auth fire workflows normally, so this
tests the label trigger without the PAT. Watch the run
(`gh run list --workflow=testflight-autofix.yml --repo tseale/two-of-us`);
success = Claude comments on the issue and labels it `needs-human` without
opening a PR. Then close the test issue. Done — report each step's
verification result to the human.

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
