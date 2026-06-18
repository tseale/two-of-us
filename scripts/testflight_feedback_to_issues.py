#!/usr/bin/env python3
"""Poll App Store Connect for new TestFlight beta feedback and file GitHub issues.

Fetches both feedback types Apple exposes via the App Store Connect API
(WWDC 2025 additions):

  - betaFeedbackScreenshotSubmissions  (tester comments, optionally with screenshots)
  - betaFeedbackCrashSubmissions       (crashes, with the symbolicated log text)

Each submission becomes one GitHub issue labeled `testflight-feedback`.
A hidden HTML marker in the issue body carries the ASC submission ID, so
re-runs are idempotent: submissions that already have an issue (open or
closed) are skipped.

Environment:
  ASC_ISSUER_ID    App Store Connect API key issuer ID
  ASC_KEY_ID       App Store Connect API key ID
  ASC_PRIVATE_KEY  Contents of the .p8 private key
  ASC_APP_ID       Numeric Apple app ID (optional; resolved from bundle ID if unset)
  ASC_BUNDLE_ID    Bundle ID used for the lookup (default com.taylorseale.twoofus)
  GITHUB_TOKEN     Token used to create issues (the workflow's default
                   GITHUB_TOKEN with `issues: write` permission works).
                   NOTE: if a downstream workflow should ever trigger off these
                   issues (e.g. label-driven automation), this must become a PAT
                   or GitHub App token — events created with the default token
                   never start other workflows.
  GITHUB_REPOSITORY  owner/repo (set automatically on Actions runners)
"""

import os
import sys
import time

import jwt  # PyJWT[crypto]
import requests

ASC_BASE = "https://api.appstoreconnect.apple.com"
GITHUB_API = "https://api.github.com"
FEEDBACK_LABEL = "testflight-feedback"
MARKER_PREFIX = "<!-- testflight-feedback-id: "
MARKER_SUFFIX = " -->"
# GitHub caps issue bodies at 65536 chars; leave room for metadata around the log.
CRASH_LOG_MAX_CHARS = 50_000


def env(name: str, default: str | None = None) -> str | None:
    """Read an env var, stripping surrounding whitespace — secrets pasted into
    GitHub's web form often carry a trailing newline, which corrupts URLs and
    auth headers."""
    value = os.environ.get(name)
    if value is None or not value.strip():
        return default
    return value.strip()


def require(name: str) -> str:
    value = env(name)
    if value is None:
        sys.exit(f"Missing required environment variable: {name}")
    return value


def asc_token() -> str:
    now = int(time.time())
    return jwt.encode(
        {"iss": require("ASC_ISSUER_ID"), "iat": now, "exp": now + 15 * 60,
         "aud": "appstoreconnect-v1"},
        require("ASC_PRIVATE_KEY"),
        algorithm="ES256",
        headers={"kid": require("ASC_KEY_ID"), "typ": "JWT"},
    )


def asc_get(path: str, params: dict | None = None) -> dict:
    resp = requests.get(
        f"{ASC_BASE}{path}",
        params=params,
        headers={"Authorization": f"Bearer {asc_token()}"},
        timeout=30,
    )
    resp.raise_for_status()
    return resp.json()


def resolve_app_id() -> str:
    if env("ASC_APP_ID"):
        return env("ASC_APP_ID")
    bundle_id = env("ASC_BUNDLE_ID", "com.taylorseale.twoofus")
    data = asc_get("/v1/apps", {"filter[bundleId]": bundle_id})["data"]
    if not data:
        sys.exit(f"No App Store Connect app found for bundle ID {bundle_id}")
    return data[0]["id"]


def list_submissions(app_id: str, kind: str) -> list[dict]:
    """kind: 'betaFeedbackScreenshotSubmissions' or 'betaFeedbackCrashSubmissions'."""
    body = asc_get(f"/v1/apps/{app_id}/{kind}",
                   {"sort": "-createdDate", "limit": 200})
    return body.get("data", [])


def crash_log_text(submission_id: str) -> str:
    try:
        body = asc_get(f"/v1/betaFeedbackCrashSubmissions/{submission_id}/crashLog")
        return (body.get("data", {}).get("attributes", {}) or {}).get("logText") or ""
    except requests.HTTPError as err:
        return f"(failed to fetch crash log: {err})"


def gh(method: str, path: str, **kwargs) -> requests.Response:
    resp = requests.request(
        method,
        f"{GITHUB_API}{path}",
        headers={
            "Authorization": f"Bearer {require('GITHUB_TOKEN')}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
        },
        timeout=30,
        **kwargs,
    )
    return resp


def ensure_label(repo: str) -> None:
    resp = gh("POST", f"/repos/{repo}/labels", json={
        "name": FEEDBACK_LABEL,
        "color": "1E6FEB",
        "description": "Auto-filed from TestFlight beta feedback",
    })
    if resp.status_code not in (201, 422):  # 422 = already exists
        resp.raise_for_status()


def existing_feedback_ids(repo: str) -> set[str]:
    """Collect ASC submission IDs already filed, from the hidden body markers."""
    seen: set[str] = set()
    page = 1
    while True:
        resp = gh("GET", f"/repos/{repo}/issues",
                  params={"labels": FEEDBACK_LABEL, "state": "all",
                          "per_page": 100, "page": page})
        resp.raise_for_status()
        issues = resp.json()
        if not issues:
            return seen
        for issue in issues:
            body = issue.get("body") or ""
            start = body.find(MARKER_PREFIX)
            if start != -1:
                end = body.find(MARKER_SUFFIX, start)
                if end != -1:
                    seen.add(body[start + len(MARKER_PREFIX):end].strip())
        page += 1


def device_summary(attrs: dict) -> str:
    parts = [attrs.get("deviceModel"), attrs.get("osVersion")]
    return ", ".join(p for p in parts if p) or "unknown device"


def metadata_block(attrs: dict) -> str:
    rows = [
        ("Submitted", attrs.get("createdDate")),
        ("Tester", attrs.get("email")),
        ("Device", attrs.get("deviceModel")),
        ("OS", attrs.get("osVersion")),
        ("Build bundle", attrs.get("buildBundleId")),
        ("Locale", attrs.get("locale")),
        ("App uptime (ms)", attrs.get("appUptimeInMilliseconds")),
        ("Battery %", attrs.get("batteryPercentage")),
        ("Connection", attrs.get("connectionType")),
    ]
    lines = ["| Field | Value |", "| --- | --- |"]
    lines += [f"| {k} | {v} |" for k, v in rows if v not in (None, "")]
    return "\n".join(lines)


def build_issue(kind: str, submission: dict) -> tuple[str, str]:
    attrs = submission.get("attributes", {}) or {}
    sub_id = submission["id"]
    comment = (attrs.get("comment") or "").strip()
    is_crash = kind == "betaFeedbackCrashSubmissions"

    if is_crash:
        title = f"[TestFlight crash] {comment or device_summary(attrs)}"
    else:
        title = f"[TestFlight feedback] {comment or device_summary(attrs)}"
    title = title[:240]

    sections = [
        f"{MARKER_PREFIX}{kind}:{sub_id}{MARKER_SUFFIX}",
        f"**Type:** {'Crash' if is_crash else 'Screenshot/comment feedback'} "
        f"(auto-filed from TestFlight)",
        metadata_block(attrs),
    ]

    if comment:
        sections.append(f"## Tester comment\n\n> {comment}")

    screenshots = attrs.get("screenshots") or []
    if screenshots:
        shots = "\n".join(
            f"- [Screenshot {i + 1}]({shot.get('url')}) "
            f"(expires {shot.get('expirationDate', 'soon')})"
            for i, shot in enumerate(screenshots)
        )
        sections.append(
            "## Screenshots\n\n"
            "_Apple's screenshot URLs expire — view promptly or pull them from "
            "App Store Connect → TestFlight → Feedback._\n\n" + shots
        )

    if is_crash:
        log = crash_log_text(sub_id)
        if len(log) > CRASH_LOG_MAX_CHARS:
            log = log[:CRASH_LOG_MAX_CHARS] + "\n… (truncated)"
        sections.append(
            "## Crash log\n\n<details><summary>Show crash log</summary>\n\n"
            f"```\n{log or '(no crash log text returned)'}\n```\n\n</details>"
        )

    return title, "\n\n".join(sections)


def main() -> None:
    repo = require("GITHUB_REPOSITORY")
    app_id = resolve_app_id()
    ensure_label(repo)
    seen = existing_feedback_ids(repo)

    created = 0
    for kind in ("betaFeedbackScreenshotSubmissions", "betaFeedbackCrashSubmissions"):
        for submission in list_submissions(app_id, kind):
            key = f"{kind}:{submission['id']}"
            if key in seen:
                continue
            title, body = build_issue(kind, submission)
            resp = gh("POST", f"/repos/{repo}/issues",
                      json={"title": title, "body": body,
                            "labels": [FEEDBACK_LABEL]})
            resp.raise_for_status()
            created += 1
            print(f"Filed issue #{resp.json()['number']} for {key}: {title}")

    print(f"Done. {created} new issue(s) filed.")


if __name__ == "__main__":
    main()
