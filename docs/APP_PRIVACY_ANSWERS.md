# App Store Connect — App Privacy Answers

Field-by-field answers for **App Privacy** in App Store Connect.
Source of truth: `docs/PRIVACY.md` and `docs/appstore/PRIVACY_NUTRITION_LABEL.md` (keep in sync).

---

## Headline answer: Data Not Collected

When ASC asks "Do you or your third-party partners collect data from this app?" → **No**.

This sets the label to **"Data Not Collected"** and skips all per-category screens.

**Why this is defensible:**
- All data lives in the **user's own private iCloud** (CloudKit container `iCloud.com.taylorseale.twoofus`). Per Apple's definition, data stored in the user's own iCloud that the developer cannot access is **not** collected by the developer.
- **No Two of Us server.** No third-party backend. The developer never receives the data.
- **No analytics, ads, telemetry, or tracking SDKs.** Only first-party Apple frameworks.
- Matches `PrivacyInfo.xcprivacy`: `NSPrivacyCollectedDataTypes` is an empty array, `NSPrivacyTracking = false`.

---

## Data types — quick reference

| Data stored in the app | Collected by developer? | Linked to user? | Used for tracking? |
|---|---|---|---|
| Baby name | **No** | — | **No** |
| Baby date of birth | **No** | — | **No** |
| Feed events (amount, time) | **No** | — | **No** |
| Sleep events (start/end) | **No** | — | **No** |
| Diaper events (type, time) | **No** | — | **No** |
| Participant display names | **No** | — | **No** |
| Optional baby/participant photos | **No** | — | **No** |
| Notes attached to events | **No** | — | **No** |

All of the above stay exclusively in the user's iCloud. The developer has no access.

---

## ASC form walkthrough

### Screen 1 — Data Collection
**"Do you or your third-party partners collect data from this app?"**
→ **No**

Selecting No lands on "Data Not Collected." You're done with the privacy label — proceed to Age Rating.

---

### If forced through per-category screens (reference)

| ASC category | Answer | Reason |
|---|---|---|
| Contact Info | Not Collected | Participant display names are user-defined, stored only in user's iCloud |
| Health & Fitness | Not Collected | Feeds/sleep/diapers are not written to HealthKit; never leave user's iCloud |
| Financial Info | Not Collected | No purchases or payment data |
| Location | Not Collected | No location APIs |
| Sensitive Info | Not Collected | None |
| Contacts | Not Collected | No Contacts framework access |
| User Content | Not Collected | Notes, photos stored in user's iCloud only |
| Browsing/Search History | Not Collected | None |
| Identifiers | Not Collected | No analytics or advertising identifiers; CloudKit records are Apple-managed |
| Purchases | Not Collected | No IAP |
| Usage Data | Not Collected | No analytics or product-interaction logging |
| Diagnostics | Not Collected | No third-party crash/analytics SDK |

**Tracking:** "Do you use data to track users?" → **No** (`NSPrivacyTracking = false`; no `NSPrivacyTrackingDomains`)

---

## Privacy Policy URL

ASC requires a public Privacy Policy URL even for "Data Not Collected."

**URL:** `https://tseale.github.io/two-of-us/`

The support page at this URL includes the full privacy policy. Paste this URL into:
- ASC → App Privacy → **Privacy Policy URL**
- ASC → App Information → **Support URL**

---

## Age Rating

Answer **None / No** to every question. Expected result: **4+**.

See `docs/appstore/PRIVACY_NUTRITION_LABEL.md` for the full age-rating table and children's-privacy notes.

---

## App Review notes (have ready)

> Two of Us is a private baby-care log used by parents and invited adult caregivers to track an infant's feeds, sleep, and diaper changes. It is not directed at children and collects no data from children. All data is stored in the user's own iCloud via CloudKit; there is no developer-operated server and no third-party SDKs, so no data reaches the developer (hence "Data Not Collected").
