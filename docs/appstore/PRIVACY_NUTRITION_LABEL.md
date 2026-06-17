# App Store Privacy Nutrition Label — Answer Key

Field-by-field answers for the **App Privacy** section in App Store Connect
(ASC → your app → **App Privacy** → *Get Started* / *Edit*). Transcribe these
directly. Source of truth: `docs/PRIVACY.md` and `TwoOfUs/PrivacyInfo.xcprivacy`
(keep all three in sync).

---

## TL;DR — the headline answer

> **"Data Not Collected."**

When ASC asks *"Do you or your third-party partners collect data from this app?"*
answer **No → "Data Not Collected."**

**Why this is correct (and defensible):**
- All baby/event data lives in the **user's own private iCloud** (CloudKit
  container `iCloud.com.taylorseale.twoofus`). Per Apple's definition, data the
  user stores in **their own iCloud** that the developer **cannot access** is
  **not** "collected" by the developer.
- There is **no Two of Us server** and **no third-party backend** — the
  developers never receive the data.
- **No analytics, ads, telemetry, or tracking SDKs.** No third-party
  dependencies at all — only first-party Apple frameworks.
- This matches `PrivacyInfo.xcprivacy`: `NSPrivacyCollectedDataTypes` is an
  **empty array** and `NSPrivacyTracking = false`.

If ASC's flow forces you through the data-type screens before letting you land
on "Data Not Collected," the answers below confirm every category is **Not
Collected**.

---

## Screen 1 — "Data Collection"

| ASC prompt | Answer |
|---|---|
| Do you or your third-party partners collect data from this app? | **No** |

Selecting **No** sets the label to **"Data Not Collected"** and skips the
remaining data-type screens. You're done with the label itself — proceed to
**Age Rating** (separate questionnaire, see below).

---

## If asked to confirm per category (reference — all "Not Collected")

Should Apple review push back, or a future version adds collection, here is the
rationale per category so you never have to re-derive it:

| Data category | Collected? | Reasoning |
|---|---|---|
| Contact Info (name, email, phone, address) | **No** | Participant *display names* are user-entered and stored only in the user's iCloud; never transmitted to the developer. |
| Health & Fitness | **No** | Feeds/sleep/diapers are **not** written to HealthKit and never leave the user's iCloud. No HealthKit entitlement. |
| Financial Info | **No** | None. No purchases, no payment data. |
| Location | **No** | No location APIs used. |
| Sensitive Info | **No** | None collected by developer. |
| Contacts | **No** | No Contacts access. |
| User Content (photos, other) | **No** | Baby name/DOB, notes, optional avatar photos stay in the user's iCloud; developer has no access. |
| Browsing / Search History | **No** | None. |
| Identifiers (User ID, Device ID) | **No** | No analytics/advertising identifiers. CloudKit user records are Apple-managed and not exposed to the developer. |
| Purchases | **No** | No IAP, no purchase history. |
| Usage Data | **No** | No analytics or product-interaction logging. |
| Diagnostics (crash, performance) | **No** | No third-party crash/analytics SDK. (Apple's own TestFlight/Xcode crash reporting is Apple-operated and out of scope for *your* declaration.) |
| Other Data | **No** | None. |

**Tracking:** *Do you use data to track users?* → **No.** (Matches
`NSPrivacyTracking = false`; no `NSPrivacyTrackingDomains`.)

---

## Age Rating questionnaire (separate from the privacy label)

ASC → **Age Rating** → *Edit*. Two of Us is a clean utility — answer **None /
No** to everything:

| Question | Answer |
|---|---|
| Cartoon or Fantasy Violence | **None** |
| Realistic Violence | **None** |
| Sexual Content or Nudity | **None** |
| Profanity or Crude Humor | **None** |
| Alcohol, Tobacco, or Drug Use or References | **None** |
| Mature/Suggestive Themes | **None** |
| Horror/Fear Themes | **None** |
| Medical/Treatment Information | **None** *(it logs care events; it does not provide medical advice/diagnosis — see note below)* |
| Gambling | **None** |
| Contests | **None** |
| Unrestricted Web Access | **No** |
| User-Generated Content | **No** *(content is private to an invite-only group of ≤ family caregivers; not public UGC)* |
| Made for Kids / directed at children | **No** — see Children's-privacy note |

**Expected result: 4+.**

> **Medical note.** Two of Us *records* a parent's observations (feeds, sleep,
> diapers); it does **not** diagnose, treat, or give medical advice. Keep the
> listing copy free of clinical claims so this stays "None." If Apple flags it,
> point to the description: it's a log/tracker, not a medical reference.

---

## Children's-privacy confirmation (have this ready for review notes)

Apple may ask because the app concerns a baby. The defensible position, per
`PRIVACY.md`:

- The app is used **by parents to record their own child's care**. It does
  **not** collect data *from* a child and has **no child-facing accounts or
  features**.
- It is **not directed at children** → **do not** enrol in *Kids Category*.
- Invite-only, ≤ small group of adult caregivers; no public access tier.

Suggested **App Review notes** snippet:

> Two of Us is a private baby-care log used by two parents (and optionally
> invited adult caregivers) to track an infant's feeds, sleep, and diaper
> changes. It is not directed at children and collects no data from children.
> All data is stored in the user's own iCloud via CloudKit; there is no
> developer-operated server and no third-party SDKs, so no data reaches the
> developer (hence "Data Not Collected").

---

## Privacy Policy URL

ASC requires a reachable **Privacy Policy URL** on the listing even when "Data
Not Collected." `docs/PRIVACY.md` is the content; publish it at a stable public
URL (e.g. GitHub Pages / a gist / the marketing site) and paste that URL into
ASC → **App Privacy → Privacy Policy URL** and the **Support URL** field.
*(This is the one outstanding to-do this doc can't satisfy on its own.)*
