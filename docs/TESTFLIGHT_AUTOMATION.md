# TestFlight feedback → GitHub issues

When a beta tester (one of the two of us) submits feedback or hits a crash in
TestFlight, it shows up as a GitHub issue within the hour — no checking App
Store Connect:

```
TestFlight feedback / crash
        │  (App Store Connect API, polled hourly)
        ▼
GitHub issue, labeled `testflight-feedback`     ← .github/workflows/testflight-feedback.yml
                                                  + scripts/testflight_feedback_to_issues.py
```

Each issue carries the tester comment, device metadata (model, OS, locale,
battery, uptime), screenshot links, and — for crashes — the crash log inline.
A hidden submission-ID marker makes the poller idempotent: re-runs never file
duplicates, even for closed issues.

## One-time setup

### 1. App Store Connect API key

The poller reads feedback via Apple's official beta-feedback endpoints (added
in the WWDC 2025 ASC API update).

1. [App Store Connect](https://appstoreconnect.apple.com) → **Users and
   Access** → **Integrations** → **App Store Connect API** → **Team Keys** →
   **+**. (Creating keys requires the Admin role.)
2. Role for the new key: **App Manager** (Admin also works; lower roles are
   unverified for the feedback endpoints).
3. Download the `.p8` file — Apple lets you download it **once**; stash it in
   your password manager. Note the **Key ID** (on the key row) and the
   **Issuer ID** (top of the page).

### 2. GitHub repo secrets

Repo → **Settings → Secrets and variables → Actions**, add:

| Secret | Value |
| --- | --- |
| `ASC_ISSUER_ID` | Issuer ID from the API Keys page |
| `ASC_KEY_ID` | Key ID of the key you created |
| `ASC_PRIVATE_KEY` | Full contents of the `.p8` file (including BEGIN/END lines) |
| `ASC_APP_ID` | Numeric Apple ID of the app (App Store Connect → app → App Information). Optional — resolved from the bundle ID if unset |

With `gh` locally, the multiline key is easier from the CLI:
`gh secret set ASC_PRIVATE_KEY --repo tseale/two-of-us < ~/Downloads/AuthKey_<KEYID>.p8`

Issue creation uses the workflow's built-in `GITHUB_TOKEN` — no PAT needed.

### 3. Smoke test

Actions → "TestFlight feedback → issues" → **Run workflow**. A green run means
the ASC credentials work end to end; it files issues only if real feedback
exists. (To verify auth locally first, see the snippet in the agent runbook
below.)

The `testflight-feedback` label is created automatically on first run.

## Day-to-day

- Submit feedback from TestFlight (screenshot → markup → share beta feedback,
  or the crash dialog). Within ~an hour an issue appears.
- Fix it however you like — by hand, or point Claude Code at it locally
  ("fix issue #41").
- **Force a poll now:** Actions → "TestFlight feedback → issues" → Run
  workflow.

## Automating the one-time setup (Claude on a Mac with computer use)

Runbook for an agent executing the setup. Ground rules:

- **Never handle the human's credentials.** At any password, passkey, 2FA, or
  CAPTCHA prompt, stop and hand control to the human, then resume.
- **Keep secret values out of the transcript and screenshots.** Pipe from the
  clipboard (`pbpaste | gh secret set …`), then clear it (`pbcopy < /dev/null`).
- **Prefer the CLI** (`gh`, `python3`); only the ASC key creation needs the
  browser.
- **Verify each step before the next; be idempotent.** Check
  `gh secret list --repo tseale/two-of-us` first and skip what exists. Never
  create a second ASC key — `.p8` files download once; if a key exists but its
  secret doesn't, stop and ask the human.

Prerequisites (human): `gh auth login` completed; browser ready to sign in to
appstoreconnect.apple.com (Admin role); macOS Screen Recording + Accessibility
granted to the computer-use tooling.

**Step 1 — ASC key (browser):** follow §1 above. The `.p8` lands at
`~/Downloads/AuthKey_<KEYID>.p8`. Then:

```sh
gh secret set ASC_ISSUER_ID   --repo tseale/two-of-us --body "<issuer-id>"
gh secret set ASC_KEY_ID      --repo tseale/two-of-us --body "<key-id>"
gh secret set ASC_PRIVATE_KEY --repo tseale/two-of-us < ~/Downloads/AuthKey_<KEYID>.p8
```

Issuer ID and Key ID are identifiers, not secrets. Ask the human whether to
archive or delete the `.p8` afterwards.

**Step 2 — verify auth and capture the app ID:**

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

A printed App ID means auth works; store it with
`gh secret set ASC_APP_ID --repo tseale/two-of-us --body "<app-id>"`.
(401 → key IDs/p8 mismatch; empty `data` → app record missing, see
docs/XCODE_CLOUD.md §1.)

**Step 3 — smoke test:**

```sh
gh workflow run "TestFlight feedback → issues" --repo tseale/two-of-us
gh run watch --repo tseale/two-of-us --exit-status
```

Report each step's verification result to the human.

## Known limitations

- **Screenshot URLs expire.** Apple's feedback screenshot links die after a
  short window; the originals stay in App Store Connect → TestFlight →
  Feedback. Write a sentence with your screenshots — the text is durable.
- **Crash symbolication.** Crash logs come from Apple as `logText`; if frames
  show as addresses, grab the symbolicated log from the Xcode Organizer
  instead.

## Re-enabling autofix later

An earlier revision of this pipeline had a second stage: a `labeled`-triggered
workflow running `anthropics/claude-code-action@v1` that triaged each feedback
issue, implemented a fix, and opened a draft PR. It was removed in favor of
issue-only mode, but the issues still carry the `testflight-feedback` label,
so restoring it is purely additive: recover
`.github/workflows/testflight-autofix.yml` from git history, add
`ANTHROPIC_API_KEY`, and switch the poller's `GITHUB_TOKEN` env to a
fine-grained PAT (Issues: read/write) stored as `TESTFLIGHT_ISSUES_TOKEN` —
required because issues created with the default token never trigger other
workflows.

## Troubleshooting

- **401 from App Store Connect** → key revoked, or `ASC_PRIVATE_KEY` missing
  its BEGIN/END lines, or Issuer/Key ID mismatch.
- **`No App Store Connect app found`** → set `ASC_APP_ID` explicitly; the
  bundle-ID lookup requires the app record to exist (docs/XCODE_CLOUD.md §1).
- **`Resource not accessible by integration` filing issues** → the workflow's
  `permissions:` block lost `issues: write`.
- **Duplicate issues** → the dedupe marker (`<!-- testflight-feedback-id: … -->`)
  was edited out of an issue body; leave the hidden comment intact.
