# Device Test Matrix

The surfaces that behave differently across hardware/OS. Run the
`TESTFLIGHT_MANUAL_CHECKLIST.md` against at least one device per row before an
App Store submission. Deployment target is **iOS 26**.

## Devices
| Device class | Why it matters | Must verify |
|---|---|---|
| iPhone Pro (Dynamic Island) | Live Activity Island layout | Sleep timer in the Island, leading/trailing/compact states |
| iPhone non-Pro (notch) | Lock-Screen Live Activity only | Lock-screen sleep timer, widgets |
| iPhone SE / smallest width | Tight layouts, `minimumScaleFactor` | Lifetime 2×2 grid, widget action buttons, no clipping |
| iPad | Portrait + landscape, regular size class | Onboarding, Home, sheets, widgets |

## Capability dimensions
| Dimension | Variants to cover |
|---|---|
| Appearance | Light, Dark (both from day one) |
| Dynamic Type | Default → XXL (no clipping, ViewThatFits paths) |
| Apple Intelligence | Available (NL log + AI summary) and unavailable (UI hides cleanly) |
| AlarmKit permission | Granted, denied (one-time prompt), undetermined |
| iCloud | Signed in (sync) and signed out (local-only degrade) |
| Network | Online, offline→reconnect, airplane mode mid-sync |

## Accounts
- **Two distinct iCloud accounts** on two devices are required for sharing,
  role changes, leave/revoke, and cross-device sync timing. The simulator and a
  single account cannot exercise these.

## Not simulator-testable (hardware only)
- Live Activities / Dynamic Island (ActivityKit doesn't run in the simulator).
- Widgets rendering/updating/deep-linking on a real Home/Lock Screen.
- AlarmKit alarms piercing Silent/Focus.
- CloudKit sharing across two real accounts; silent push delivery.
