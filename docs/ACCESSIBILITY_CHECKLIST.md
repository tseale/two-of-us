# Accessibility Checklist

A focused end-to-end pass (its own session). The design system is built for this
(semantic tokens, dot+words urgency, Reduce-Motion awareness), but it has never
been audited start to finish — a release gate per `RELEASE_POLISH_PLAN.md` §17.

## VoiceOver (every screen)
- [ ] Onboarding (tour → baby → you → invite) reads in order; page progress
      announces "Page X of N"; decorative CradleMark is silent.
- [ ] Join flow; "connecting…" state announces; Finish state is clear.
- [ ] Home: log tiles, time-since, Today ribbon (combined label), timeline rows
      with participant attribution.
- [ ] Sheets: Feed (preset chips selected state), Diaper (selected type), Edit
      (incl. the note field).
- [ ] History & Stats: charts have meaningful labels or summaries; insight card.
- [ ] Settings → People: section has a heading/count; role pills read; Manage
      Data destructive flow is navigable.
- [ ] Transient banners (error/toast) are announced.

## Dynamic Type
- [ ] Every screen at XXL with no clipping or truncation of essential info.
- [ ] `minimumScaleFactor` spots stay legible (lifetime grid, widget buttons,
      Today metrics).
- [ ] ViewThatFits fallbacks engage where used.

## Color & contrast
- [ ] Urgency is conveyed by **dot + words**, not hue alone.
- [ ] Urgency amber/red text and role-pill fills meet AA in **dark mode**
      specifically (`Colors.swift`, `SettingsView` role pills).
- [ ] Accent-on-material text (banners, toasts) meets contrast in both schemes.

## Motion & haptics
- [ ] Reduce Motion: crossfades replace springs/morphs; ambient re-tints calm.
- [ ] Confirmations don't rely on sound; haptics + visible state back every log.

## Tooling
- [ ] Run Accessibility Inspector audits per screen; capture and attach output.
- [ ] VoiceOver rotor / focus order sane on the busiest screen (Home).
