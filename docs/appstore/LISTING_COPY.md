# App Store Listing Copy

Ready-to-paste metadata for the App Store Connect listing. Character limits are
Apple's; counts noted so nothing gets silently truncated. Tone matches the
brief: calming, warm, "made for us" — not clinical. Avoid medical claims (keeps
the age rating at 4+; see `PRIVACY_NUTRITION_LABEL.md`).

> A `fastlane deliver`-compatible `metadata/` tree mirrors this file under
> `fastlane/metadata/en-US/` if/when you wire up fastlane; until then, copy from
> here straight into ASC.

---

## App Name — 30 char max

**`Two of Us`** *(9)*

⚠️ **Uniqueness check required.** "Two of Us" is a common phrase and may already
be claimed on the App Store. If taken, fall back (still ≤30):
- `Two of Us — Baby Tracker` *(24)*
- `Two of Us: Baby Log` *(19)*
- `Two of Us Baby` *(14)*

## Subtitle — 30 char max

Primary: **`Baby tracking for two parents`** *(29)*

Alternates:
- `Feeds, sleep & diapers in sync` *(30)*
- `Newborn tracking, shared` *(24)*

## Promotional Text — 170 char max *(editable anytime without a new build)*

> `Track Miller's feeds, sleep, and diapers together — both parents, one shared timeline, synced in seconds over iCloud. No account, no ads, no clutter.` *(149)*

Generic (if you'd rather not name the baby in a public listing):

> `Track your newborn's feeds, sleep, and diapers together. Both parents, one shared timeline, synced in seconds over iCloud. No account, no ads, no clutter.` *(154)*

## Keywords — 100 char max, comma-separated, **no spaces after commas**

> `baby tracker,newborn,feeding,breastfeeding,diaper,sleep,nursing,bottle,infant,log,parents,care` *(94)*

Notes:
- Don't repeat words already in the **name/subtitle** (Apple indexes those
  separately) — that's why "two/us" aren't in keywords.
- Singular forms index plurals too; don't waste characters on both.
- Swap `breastfeeding`→`pumping` or `feeding`→`tracker` to chase different terms.

## Description — 4000 char max

```
Two of Us is a calm, private baby tracker built for two parents sharing the
care of one little one. Log a feed, a nap, or a diaper change in a tap or two —
because you're usually holding a baby with the other hand — and your partner
sees it on their iPhone within seconds.

No account to create. No ads. No clutter. Just the two of you and one shared,
up-to-the-minute picture of your baby's day.

QUICK TO LOG
• One-tap logging for feeds, sleep, and diapers — designed for one-handed use.
• Start a feed or sleep timer and stop it later; Two of Us tracks the duration.
• Add a quick note or who logged it when it matters.

SHARED IN REAL TIME
• Both parents, one timeline. Updates sync over iCloud in about ten seconds.
• Invite your co-parent with a single link — no usernames, no passwords.
• Optional caregiver access: a grandparent or sitter can log without changing
  your settings.

ALWAYS A GLANCE AWAY
• Lock Screen and Home Screen widgets show time since the last feed at a glance.
• A Live Activity keeps an active feed or sleep timer on your Lock Screen and in
  the Dynamic Island.
• "Hey Siri, log a diaper change" — hands-free when you have none to spare.

SEE THE PATTERNS
• Clean charts reveal feeding and sleep rhythms as they emerge.
• Catch the long stretches and the cluster days without spreadsheets.

PRIVATE BY DESIGN
• Your data lives in your own iCloud — there is no Two of Us server.
• No tracking, no analytics, no third-party SDKs, no ads. Ever.
• Only the people you invite can see your baby's data, and you can remove
  access at any time.

Beautiful in light and dark mode, built entirely with native iOS technology so
it feels right at home on your iPhone.

Made with love, for the two of you.
```
*(~1,690 chars — well under the 4000 limit.)*

> If you renamed the app away from a bare "Two of Us," keep the first line's
> product name in sync with the final App Name.

## What's New (release notes) — 4000 char max

For **1.0**:

```
Hello, world — and hello, little one.

This is the first public release of Two of Us: a calm, private way for two
parents to track feeds, sleep, and diapers together, synced over iCloud with no
account and no ads.

• One-tap logging built for one-handed use
• Real-time sync between both parents
• Lock Screen and Home Screen widgets
• Live Activities for active feed and sleep timers
• Log with Siri
• Feeding and sleep charts
• Full light and dark mode

Thank you for letting us be a small part of your days (and nights).
```

---

## Other listing fields (quick reference)

| Field | Value / source |
|---|---|
| **Primary category** | Health & Fitness *(or Lifestyle — see note)* |
| **Secondary category** | Lifestyle |
| **Support URL** | Publish `docs/PRIVACY.md` + a contact route; reuse the privacy host. |
| **Marketing URL** *(optional)* | Optional; omit for v1 if there's no site. |
| **Copyright** | `© 2026 Taylor Seale` |
| **Bundle ID** | `com.taylorseale.twoofus` |
| **Privacy Policy URL** | Required — see `PRIVACY_NUTRITION_LABEL.md`. |

> **Category choice.** *Health & Fitness* is the closest fit and where parents
> look, but it can invite extra scrutiny on medical claims — which the copy
> deliberately avoids. *Lifestyle* is the safer, lower-friction pick. Either is
> defensible; recommend **Health & Fitness** primary / **Lifestyle** secondary,
> and flip if review pushes back.
