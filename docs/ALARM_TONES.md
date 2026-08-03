# Alarm tones

The AlarmKit alarms (interval feed reminder + night-slot alarm) can ring with
either the system alarm sound or a sound file bundled in the app — that's the
entire API surface (`AlertConfiguration.AlertSound`: `.default` / `.named`).
There is no access to Apple's built-in ringtone/alarm library and no volume
control (alarms always ring at ringtone volume, through Silent and Focus).

The per-device choice lives in Settings → Reminders → Alarm sound
(`LocalPrefs.alarmTone`, applied by both alarm managers at schedule time — a
tone change re-arms any pending alarm, since the sound is baked in when the
alarm is scheduled).

## The tones

All three are synthesized from scratch by `scripts/make_alarm_tones.py`
(numpy, no samples — nothing to license) and shipped as ima4 `.caf` in
`TwoOfUs/Resources/Sounds/`. Design goal: gentler than the system alarm — a
3am feed alarm shouldn't spike anyone's heart rate — but with enough mid-band
energy to actually wake a parent once it loops.

| Tone | Character | Construction |
|---|---|---|
| **Nightlight** (default) | Music-box lullaby arpeggio in A major | Free-bar partials (1 · 2.76 · 5.40 · 8.93), 10s |
| **Sunrise** | Brighter kalimba figure in D major | Same bar physics, dominant fundamental, softer attack, 9s |
| **Bells** | Slow soft ding-dong (E→C♯), twice | Church-bell partial stack incl. hum + minor-third tierce, 11s |
| System | Apple's default alarm sound | — |

Shared construction: additive synthesis with per-partial exponential decay, a
+3-cent detuned ghost voice for warmth, decorrelated stereo convolution reverb
(decaying-noise IR), peak −1 dBFS, and a fade to silence so the system's alarm
loop restarts cleanly.

## Regenerating / adding a tone

```bash
python3 scripts/make_alarm_tones.py      # writes .wav next to the script
afconvert -f caff -d ima4 scripts/alarm-<tone>.wav TwoOfUs/Resources/Sounds/alarm-<tone>.caf
```

Then add a case to `AlarmTone` (TwoOfUs/Alarms/AlarmTone.swift). Files must
stay under 30 seconds (the notification-sound rules apply to the
`UNNotificationSound` fallback path, which reuses the same files).
