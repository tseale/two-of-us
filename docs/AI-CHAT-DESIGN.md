# Ask about Miller — on-device chat over the log

**Status: v1 shipped on the iOS 27 feature branch, 2026-09-18.** This is the
§5 decision from `docs/IOS-27-UPGRADE-PLAN.md`: build a small chat or let the
new Siri cover it? Answer: both, with a deliberately narrow chat.

## Why build it at all

The iOS 27 Siri now resolves our `CareEventEntity` records and our query
intents, so "when did Miller last eat" works hands-free without the app. What
Siri doesn't do is *reason over a span*: "how were the nights this week",
"is he eating more than last week", "what's the longest nap lately". Those
need the log read and summarized, and that is exactly what an on-device
Foundation Models session with one tool does well. The chat is for questions
with a range in them; Siri is for the one-fact questions.

## Shape

- **Entry:** Stats → "Ask about Miller" card (shown when the AI toggle is on,
  the model is available, and there is any data). Sheet, large detent,
  keyboard up on open.
- **Session:** `AskSession` (`TwoOfUs/AI/AskSession.swift`) — one on-device
  `LanguageModelSession` per sheet, kept for follow-ups ("and the day
  before?"). Instructions pin the voice (calm, third person, 2–3 sentences,
  no lists, no medical advice — "ask the pediatrician") and require calling
  the tool before answering.
- **Tool:** `CareEventsTool` (`TwoOfUs/AI/CareEventsTool.swift`) — the only
  tool. Arguments: `kind` (feed/sleep/diaper/note/all) and `days` (1–30,
  guided range). Returns up to 80 events as one line each, newest first, with
  amounts, durations, diaper types, logger, and an honest "No … logged" /
  "(N older events omitted)". Reads through `CareEventCatalog`, the same App
  Group store the intents use. Pure `render` is unit-tested.
- **UI:** `AskSheet` — starter questions as tappable cards, user bubbles in
  the indigo gradient, answers in a surface card with the AI gradient
  hairline (same boundary treatment as the generated Stats cards), a
  "Reading the log…" row while the tool runs, caption "Answers are generated
  on your iPhone from your own logs. Not medical advice."

## Deliberate limits

- **One tool.** A 3B model with one well-described tool is reliable; the same
  model juggling several (stats, schedule, settings) is not. Add a second
  tool only for a question class the log lines can't answer.
- **On-device only.** No Private Cloud Compute here. The weekly patterns card
  already uses PCC for the "read two weeks of raw history" case; questions
  are short and the tool output is bounded, so 8K is enough and the privacy
  story for chat stays "never leaves the phone".
- **No streaming.** Answers are 2–3 sentences; the spinner is honest enough.
- **No writes.** Logging stays with the log intents and the app UI. A chat
  that can log is a chat that can mislog at 3am.

## Follow-ups worth doing

- **`SpotlightSearchTool`** (iOS 27, `_CoreSpotlight_FoundationModels`):
  semantic search over the same `CareEventEntity` index that
  `SpotlightIndexer` maintains. Free-text questions ("when did he have that
  rough night with the rash note?") are where it beats `CareEventsTool`'s
  kind/days filter. Add as a second tool once the first has been used for a
  while and its misses are known.
- **Escalate long spans to PCC.** If "compare this month to last" turns out
  to be a common question, route `days > 14` to `PrivateCloudComputeLanguageModel`
  with the `HistoryDigest` — same session shape, different model — and label
  the answer as the patterns card does.
- **Siri hand-off.** Expose "Ask about Miller" as an intent taking a question
  parameter so the same session can be invoked from Siri/Shortcuts.
- **Transcript hygiene.** Sessions are per-sheet today; if follow-up chains
  get long enough to hit the context, adopt the iOS 27 rolling-window
  transcript utilities (session 242).
