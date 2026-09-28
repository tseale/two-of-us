#!/usr/bin/env python3
"""Pull today's activities for a student from Brightwheel's internal API.

Prototype for the Brightwheel -> Two of Us sync explored in
docs/BRIGHTWHEEL-INTEGRATION.md. Uses the same unofficial, cookie-authenticated
API as the web app at schools.mybrightwheel.com (there is no public API).

Auth: log into https://schools.mybrightwheel.com in a browser, copy the value
of the `_brightwheel_v2` cookie from DevTools (Network tab -> any XHR ->
Cookies), and provide it via:

  BRIGHTWHEEL_COOKIE      the cookie value itself, or
  BRIGHTWHEEL_COOKIE_FILE path to a file containing it
                          (default ~/.config/twoofus/brightwheel_cookie)

Optional:
  BRIGHTWHEEL_STUDENT     student first name to select (default: first student)

Usage:
  python3 scripts/brightwheel_sync.py [--date YYYY-MM-DD] [--out FILE]

Writes structured events as JSON (default brightwheel_import.json):
  {"source": "brightwheel", "student": ..., "fetched_at": ..., "events": [
    {"type": "feed"|"sleep"|"diaper"|"photo"|"note"|..., "timestamp": ...,
     "ended_at": ..., "note": ..., "details": {...}, "brightwheel_id": ...}]}

Stdlib only — no third-party dependencies.
"""

import argparse
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import date, datetime
from pathlib import Path
from typing import Any, Iterator, Optional

BASE_URL = "https://schools.mybrightwheel.com/api/v1"
DEFAULT_COOKIE_FILE = Path.home() / ".config" / "twoofus" / "brightwheel_cookie"

# Brightwheel action_type -> Two of Us event type. The full taxonomy (from the
# web app bundle): ac_food, ac_nap, ac_potty, ac_photo, ac_video, ac_note,
# ac_checkin, ac_absence, ac_incident, ac_meds, ac_health_check,
# ac_health_screen, ac_observation, ac_kudo, ac_learning_activity,
# ac_internal_checkin, ac_activity.
ACTION_TYPE_MAP = {
    "ac_food": "feed",
    "ac_nap": "sleep",
    "ac_potty": "diaper",
    "ac_photo": "photo",
    "ac_video": "photo",
    "ac_note": "note",
    "ac_checkin": "checkin",
    "ac_incident": "incident",
    "ac_meds": "medication",
    "ac_health_check": "health",
    "ac_health_screen": "health",
    "ac_observation": "note",
    "ac_kudo": "note",
    "ac_learning_activity": "activity",
    "ac_activity": "activity",
}


class BrightwheelClient:
    def __init__(self, cookie: str) -> None:
        self.cookie = cookie.strip()

    def _get(self, path: str, params: Optional[dict[str, Any]] = None) -> dict:
        url = f"{BASE_URL}{path}"
        if params:
            url += "?" + urllib.parse.urlencode(params)
        req = urllib.request.Request(
            url,
            headers={
                "Cookie": f"_brightwheel_v2={self.cookie}",
                "Accept": "application/json",
                # The API rejects obvious non-browser agents; present as the browser
                # the cookie came from.
                "User-Agent": (
                    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                    "AppleWebKit/537.36 (KHTML, like Gecko) "
                    "Chrome/128.0.0.0 Safari/537.36"
                ),
            },
        )
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                return json.load(resp)
        except urllib.error.HTTPError as e:
            if e.code in (401, 403):
                sys.exit(
                    f"Brightwheel returned {e.code} — the cookie has expired or was "
                    "rejected. Log into schools.mybrightwheel.com and copy a fresh "
                    "_brightwheel_v2 cookie."
                )
            raise

    def me(self) -> dict:
        return self._get("/users/me")

    def students(self, guardian_id: str) -> list[dict]:
        data = self._get(f"/guardians/{guardian_id}/students", {"include[]": "schools"})
        return data.get("students", [])

    def activities(
        self, student_id: str, start: date, end: date
    ) -> Iterator[dict]:
        page = 0
        while True:
            data = self._get(
                f"/students/{student_id}/activities",
                {
                    "page": page,
                    "page_size": 100,
                    "start_date": start.isoformat(),
                    "end_date": end.isoformat(),
                    "include_parent_actions": "false",
                },
            )
            batch = data.get("activities", [])
            if not batch:
                return
            yield from batch
            page += 1


def parse_details(activity: dict) -> dict:
    """Best-effort extraction of typed details from an activity.

    details_blob shapes vary by action_type and are not formally documented;
    keep whatever we find and pass the raw blob through for inspection.
    """
    blob = activity.get("details_blob") or {}
    details: dict[str, Any] = {}
    tags = blob.get("tags") or []
    if tags:
        details["tags"] = tags

    action_type = activity.get("action_type")
    if action_type == "ac_potty":
        lowered = [str(t).lower() for t in tags]
        details["wet"] = any("wet" in t for t in lowered)
        details["dirty"] = any(t in ("bm", "dirty", "soiled") or "bm" in t for t in lowered)
    elif action_type == "ac_food":
        for key in ("amount", "unit", "food_type", "meal"):
            if blob.get(key) is not None:
                details[key] = blob[key]
        if activity.get("menu_item_tags"):
            details["menu_items"] = activity["menu_item_tags"]
    elif action_type == "ac_nap":
        for key in ("start_time", "end_time", "duration"):
            if blob.get(key) is not None:
                details[key] = blob[key]

    media = activity.get("media") or {}
    if media.get("image_url"):
        details["image_url"] = media["image_url"]
    video = activity.get("video_info") or {}
    if video.get("downloadable_url"):
        details["video_url"] = video["downloadable_url"]

    # Keep unrecognized blob keys so we learn the real schema from live data.
    leftover = {k: v for k, v in blob.items() if k not in ("tags",) and k not in details}
    if leftover:
        details["raw"] = leftover
    return details


def to_event(activity: dict) -> Optional[dict]:
    action_type = activity.get("action_type", "")
    event_type = ACTION_TYPE_MAP.get(action_type)
    if event_type is None:
        return None
    actor = activity.get("actor") or {}
    return {
        "type": event_type,
        "brightwheel_action_type": action_type,
        "brightwheel_id": activity.get("object_id"),
        "timestamp": activity.get("event_date") or activity.get("created_at"),
        "created_at": activity.get("created_at"),
        "note": activity.get("note"),
        "room": (activity.get("room") or {}).get("name"),
        "staff": " ".join(
            p for p in (actor.get("first_name"), actor.get("last_name")) if p
        )
        or None,
        "details": parse_details(activity),
    }


def load_cookie() -> str:
    cookie = os.environ.get("BRIGHTWHEEL_COOKIE")
    if cookie:
        return cookie
    path = Path(os.environ.get("BRIGHTWHEEL_COOKIE_FILE", DEFAULT_COOKIE_FILE))
    if path.exists():
        return path.read_text().strip()
    sys.exit(
        "No cookie found. Set BRIGHTWHEEL_COOKIE or put the _brightwheel_v2 "
        f"cookie value in {path} (see module docstring)."
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--date",
        type=date.fromisoformat,
        default=date.today(),
        help="Day to fetch (YYYY-MM-DD, default today)",
    )
    parser.add_argument(
        "--out", default="brightwheel_import.json", help="Output JSON path"
    )
    args = parser.parse_args()

    client = BrightwheelClient(load_cookie())

    me = client.me()
    guardian_id = me["object_id"]
    print(f"Signed in as {me.get('first_name')} {me.get('last_name')}")

    students = client.students(guardian_id)
    if not students:
        sys.exit("No students found for this guardian account.")

    wanted = os.environ.get("BRIGHTWHEEL_STUDENT", "").strip().lower()
    student = students[0]["student"]
    if wanted:
        for entry in students:
            if entry["student"].get("first_name", "").lower() == wanted:
                student = entry["student"]
                break
        else:
            sys.exit(f"No student named {wanted!r} on this account.")
    print(f"Student: {student['first_name']} {student['last_name']}")

    events = []
    skipped: dict[str, int] = {}
    for activity in client.activities(student["object_id"], args.date, args.date):
        event = to_event(activity)
        if event is None:
            key = activity.get("action_type", "?")
            skipped[key] = skipped.get(key, 0) + 1
            continue
        events.append(event)
    events.sort(key=lambda e: e["timestamp"] or "")

    result = {
        "source": "brightwheel",
        "student": {
            "first_name": student["first_name"],
            "last_name": student["last_name"],
            "brightwheel_id": student["object_id"],
        },
        "date": args.date.isoformat(),
        "fetched_at": datetime.now().astimezone().isoformat(timespec="seconds"),
        "events": events,
    }
    Path(args.out).write_text(json.dumps(result, indent=2) + "\n")
    print(f"Wrote {len(events)} events to {args.out}")
    if skipped:
        print(f"Skipped unmapped action types: {skipped}")


if __name__ == "__main__":
    main()
