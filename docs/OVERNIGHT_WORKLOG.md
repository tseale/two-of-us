# Overnight autonomous session — worklog

Running autonomously while Taylor sleeps (started 2026-07-12 ~22:10). Goal: work
the pre-App-Store backlog — accessibility, CloudKit schema/sync review, edge
cases — testing + fixing + logging. Branch `release-polish-batch-1`. Local
commits only (no push — pushing `main` triggers TestFlight). Gates that must stay
green: `make build`, `make test` (76 unit tests), `make uitest` (UI smoke).

This file is the source of truth for what's done — a continuation reads it first.

## Legend
✅ done & verified · 🔧 in progress · ⏭️ queued · 🔎 finding (noted, not fixed) · ⚠️ needs device/manual

## Backlog (ordered)
- 🔧 **A11y-1** Dynamic Type: make `AppFont.display`/`hero` actually scale (Typography.swift)
- ⏭️ **A11y-2** Urgency non-color cue + de-alias `accentDiaper`==`urgencyAmber`
- ⏭️ **A11y-3** VoiceOver: "Wake up" button absorbed into the sleep card element (SleepActiveCard)
- ⏭️ **CK-1** CloudKit schema review: Schema.swift + RecordMapping.swift round-trip completeness
- ⏭️ **CK-2** Sync review: SyncManager conflict/absorb, hold-queues, zone/share edge cases
- ⏭️ **EDGE-1** Active-sleep broken sliver on History swimlane (DayRibbon anchor) — audit high
- ⏭️ **EDGE-2** "Invite my partner" tappable with empty names → co-parent joins empty zone (OnboardingView)
- ⏭️ **EDGE-3** JoinFlow stuck state — add escape hatch after patience window
- ⏭️ **OB-1** Onboarding: keyboard covers Continue; blank-page-on-swipe

## Change log
_(append newest last)_
