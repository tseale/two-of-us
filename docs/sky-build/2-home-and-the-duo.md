# Home and the Duo layout: map for the sky port

> A map of Home and the Duo layout for the port.
> Written on 22 Nov 2026 by a read-only agent, against the branch at about commit `cd2b979` (the app as `origin/main` `3583e43` plus the sky lab). Line numbers are from that day and will drift. It is working context for building the painted hill (`docs/SKY_BUILD_PLAN.md`), not a maintained document.


Root: `the repository root` (branch `claude/trusting-ptolemy-jz35il`). Paths below are relative to it. Nothing was built or run: every number comes from constants, comments, docs and tests, not from a device. Deployment target is iOS 26.0 (`project.yml:5`), not 17.

## 1. View tree and where the sky sits

**Above Home**
- `TwoOfUs/App/RootView.swift:96-104`: `VStack { [demo pill row, bg-coloured]; routedContent }`, with overlays for the error banner (143), celebration (147, z 2) and launch curtain (161-174, z 3).
- `RootView.swift:329-344`: `TabView { HomeView … }.tabBarMinimizeBehavior(.onScrollDown)`. The tab bar is system glass.

**`HomeView.body`** (`TwoOfUs/Features/Home/HomeView.swift:151-328`)
- `NavigationStack { GeometryReader { ZStack(.topLeading) { … } } }`, nav bar hidden (225).
- `.background(AppColor.bg)` on the reader (222) is the bottom layer.
- All sheets, tasks and refresh hang on this one container (226-326).

**The phone page, `compactList`** (344-501)
- `List` (plain, `.scrollContentBackground(.hidden)` 460) with these rows:
  - `header` (385);
  - ONE row holding `TimelineView(.periodic by 1 s) { VStack(spacing 12) { heroCard; logButtons; sleepCard; snooCards; scheduleRow } }` (386-436);
  - checklist (444);
  - the timeline, one list row per entry, on card-shaped row backgrounds (449, 2907-2941).
- **The sky is the List's `.background { SkyBackground(location:, leadingFeather:) }` (461-464).** It does not scroll; the header and cards scroll over it.
- `.loggedToast` (465) is applied after the background, so the toast sits in front of the list.

**`SkyBackground`** (`TwoOfUs/DesignSystem/SkyBackground.swift:64-99`)
- `Group { ground }.ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)`.
- `ground` is plain `AppColor.bg` under Reduce Transparency or Increase Contrast; otherwise `TimelineView(.everyMinute) { SkyScene }`.
- `SkyScene` (130-165) is a `GeometryReader` with a ZStack, back to front: gradients and glows, `StarField` (night) or sun and clouds (day), moon, four blurred ridges with mist, grain image.

| Display | What is in the body ZStack | Sky frame |
|---|---|---|
| Ordinary iPhone | `compactList()` only, framed to the reader (183-192) | List frame is the safe area; `ignoresSafeArea` takes it to the whole display (402 × 874), under status bar, tab bar and home indicator |
| Duo closed | Same tree. `readerSaysCover` (188-190) gives 20 pt margins and 22 pt above the header (377-385) | List is 382 × 644; sky extends under the 84 pt strip and the 34 pt foot, so 466 × 678 |
| Duo open, landscape | (a) `spreadBehindPhone` (596-617): `ZStack { SkyBackground(showsOrb: false, companion: phoneSky); spreadDetailsPage(grid) }` framed 867 × 635. (b) Over it, the same `compactList(spread:)` at `PhonePage.frame`, x 485–867 (`TwoOfUs/Features/Shared/PhonePage.swift:34-41`) | Leading sky fills 951 × 669. Phone-page sky is x 485–951, y 0–669 (466 × 669), masked by an 18 pt leading fade (`SkyBackground.swift:66-77`) |

- Open Duo z-order, back to front: bg, leading sky, leading title and cards, phone-page sky, list rows, toast.
- So on the open Duo there are **two sky views, each with its own minute clock**. `SkyCompanion` (`HomeView.swift:590-594`) exists only so the old ridges and glow meet at the fold.
- **No sky at all** on iPad panes, the Duo open in portrait (`.tall`) or the Duo on its side (`.short`): `panes()` (523-573) uses plain lists on `AppColor.bg`.
- A Split View half or compact iPad window gets `compactList`, so it gets a sky at an arbitrary size.

## 2. How the app knows it is a Duo, closed or open

- **No model check and no fold API.** The iOS 27.1 APIs (`reservedRegions`, `onHingeChange`) are deliberately unused (`docs/IPHONE_DUO.md:278-286`).
- **Compact or not:** size classes only. `ScreenShape.isCompact` is `horizontal != .regular && vertical != .compact` (`TwoOfUs/Features/Shared/PaneLayout.swift:22-25`), read at `HomeView.swift:9-10, 164`.
- **Closed (cover):** compact, phone idiom, and a side safe-area inset greater than 0 (`HomeView.swift:188-190`). The list's own readings are a fallback (377-378, measured at 469-500).
- **Open, landscape (spread):** not compact, and `PaneLayout.resolve` returns `.wide` (display width ≥ height, `PaneLayout.swift:153-160`), and `SpreadGrid(layout:isPhone:)` is non-nil (`TwoOfUs/Features/Shared/SpreadGrid.swift:238-245`; `HomeView.swift:166-170`).
- **Fold position:** the display midline, a 40 pt band (`PaneLayout.swift:75, 155-157`).
- **How it learns of open/close:** only by the size-class environment and the reader's proxy changing, which re-runs `body`.
  - There is no `onChange`, no event, no transition and no animation. The leading page appears in the same frame as the layout swap.
  - The phone page keeps its identity because `if layout == nil || grid != nil` (180) holds in both states.
  - Opening in portrait makes that condition false and destroys the list.
- **One existing layout observer:** `RootView.swift:112-132` runs `.onChange(of: PaneLayout.resolve(…), initial: true)` and publishes `\.spreadSpine` (`TwoOfUs/Features/Shared/SpreadSpine.swift:78-91`). It is non-nil exactly while the Duo is open in landscape.

**Where an opening cue could be raised**
- `.onChange(of: grid != nil)` on the ZStack at `HomeView.swift:171-195`, or `.onChange(of: spreadSpine != nil)` via the environment.
- `onAppear` of `spreadBehindPhone` also fires on cold launch and tab switch while already open, so it cannot tell "opened" from "appeared open".
- The leading cards (`spreadDetailsPage`, 640-672) are a separate sibling from the leading sky (610-614), so they can be held back independently.
- Unknown from the code: what the system shows during the physical opening, and whether intermediate sizes pass through.

**What the leading page shows** (`HomeView.swift:640-719`)
- Frame: x 97.5–447.5, title at y 22, first card at y 103, last card ends at y 635 (`SpreadGrid.swift:23-28, 178-228`; `TwoOfUsTests/SpreadGridTests.swift:40-66`).
- Title is 34 pt rounded bold over a subheadline (`TwoOfUs/Features/Shared/PageTitle.swift:43-67`), text directly on the sky.
- Cards are opaque, radius 18, 12 pt apart, and one always stretches so the column ends on the foot line.

| Moment (683-691) | Title / subtitle | Cards |
|---|---|---|
| 5–10 AM | "Last night" / "how the night went" | "Asleep", "Who was up", "His week of nights" |
| Day | "The day so far" / "against his usual" | "Today, between you", "Note from …", "His rhythm, by this time", "Bottles through the day" |
| From 5 PM | "<Name>'s book" / date, plus a 52 pt "WEEK n" ring at the title's right (722-736) | photo, "Today's highlights", "A month ago today / Coming up" |
| Night window open, with a co-parent | "Tonight" / "the two of you", plus partner avatar 52 pt at 60 % | "<Partner> is asleep until …", "Asleep so far", "Up with him tonight", week of nights |

- Without a co-parent the night page falls back to the morning or evening page (686).
- Home's spread draws no margin avatar; only the other tabs do (`TwoOfUs/Features/Shared/SpreadScaffold.swift:130-136`).
- Clear sky on the spread: x 0–97.5 full height; the y 0–103 frieze; the gutter x 447.5–485 (phone sky fully opaque from 503); the 34 pt foot; the strip.

## 3. Geometry the sky needs

**Nothing publishes frames today.** There is no `PreferenceKey`, `anchorPreference`, named coordinate space or `matchedGeometryEffect` anywhere in `TwoOfUs/` (grep). What exists:
- `onGeometryChange` at `HomeView.swift:469-500`: top inset, side inset, full height, closed page only.
- `onGeometryChange` at `TodayHeroCard.swift:834`: a label width.
- `proxy.frame(in: .global)` at `PaneLayout.swift:128` and `HomeView.swift:471`.

| Item | Where it is in code | Surface |
|---|---|---|
| Display, safe area, strip side | body reader `proxy` (`HomeView.swift:165, 188`); `PaneLayout` `fullHeight`, `band`, `topInset`, `topOffset` (`PaneLayout.swift:119-170`); `SpreadGrid.marginSide` | — |
| Header | `HomeView.swift:1686-1718`. Avatar 60, spacing 14, name 34 pt, age subheadline, gear 44. Row insets: top 22 / sides 20 on the Duo, top 8 / sides 16 on a slab (385). Name and age widths are text and unmeasured | Text directly on sky, no scrim. Avatar is an opaque circle. Gear is an opaque `AppColor.card` circle |
| Today card | `TwoOfUs/Features/Home/TodayHeroCard.swift:248-410`. Padding 16, strip 62, radius 18; about 200 pt tall. Top is at header + 2 + 4: about y 88 on the cover, about 136 on a slab | **Opaque** (`surfaceCard`, `TwoOfUs/DesignSystem/Colors.swift:141-150`) |
| Feed and Diaper tiles | `TwoOfUs/Features/Home/LogButtons.swift:68-163`. Min content 96 + padding 18 × 2, radius 20, 12 pt gap | **Glass**: `glassEffect(.regular.tint(18 %).interactive())` (`Colors.swift:132-135`), in one `GlassEffectContainer` |
| Sleep, awake | The Sleep tile, full width, same builder (`LogButtons.swift:88-92`) | **Glass**, standalone |
| Sleep, asleep | `TwoOfUs/Features/Sleep/SleepActiveCard.swift:301-357`. Tall layout (padding 20, 48 pt timer) where full height ≥ 700; short layout (padding 16) on the Duo and SE (`HomeView.swift:349`). Radius 22. Wake slide is 56 pt high, 80 % width (`TwoOfUs/Features/Shared/SlideToConfirmView.swift:38-46`). A SNOO sleep has no slide | **Glass**, with a glass capsule inside (`SlideToConfirmView.swift:81`) |
| Tonight card, Up next, SNOO card, checklist | `HomeView.swift:2200, 2356`; `TwoOfUs/SNOO/SnooSuggestionCard.swift:69`; `TwoOfUs/Features/Setup/SetupChecklistCard.swift:88` | Opaque |
| Timeline card | Row backgrounds, radius 20 (`HomeView.swift:2907-2941`). When empty, the header and empty state sit on the sky (2540-2548) | Opaque |
| Toast | `TwoOfUs/Features/Home/LoggedToast.swift:60-69`, at the list's foot | Opaque `card2` capsule with shadow |
| Tab capsule or bar | System (`RootView.swift:329-344`); minimises on scroll. **Not measurable**: only the safe-area insets | System glass |
| Dynamic Island, Wi-Fi, battery | **No app code knows their frames.** Only the 84 pt strip width is measurable. The island grows while the app's sleep Live Activity runs; it is started in `TwoOfUs/Store/EventStore.swift:481-485` and not in demo mode | System |

- The lab's layout tables (`…/design/sky-lab/lab/core.js:445-463`, `…/skies/hill-painted.js:119-120, 228-229`) agree with these constants: avatar at (20, 22), gear at x 318, first card at y 88.6 on the cover.
- Those tables are the lab's own HTML measured at default text size with the name "Miller". The strip's island and glyph positions are its guesses (`lab/chrome.js:798-818`).
- Sky space equals `.global` on the slab and cover. On the spread, subtract the phone page's x.
- Rows scroll under the status bar and foot (`SpreadScaffold.swift:276-281` notes this behaviour).

## 4. Starting and ending a sleep by hand

**Start**
- Sleep tile `Button { Haptics.tap(); action() }` (`LogButtons.swift:106`), with `PressableTileStyle` (245-258).
- `onSleep: startSleep` (`HomeView.swift:1933`) calls `HomeView.startSleep()` (2488-2493).
- That calls `store.startSleep()` (`EventStore.swift:463-491`), then `showToast("Started sleep") { store.cancelSleep(event) }`.
- The store call is synchronous on the main thread: insert, save, sync enqueue, Live Activity, widget reload, reminders, Siri donation.
- The tile exists only when he is not at daycare (409-411), sleep is tracked, and no sleep is active.

**End**
- Wake slide: `onWake` (`SleepActiveCard.swift:245-251`) calls `endSleep` (`HomeView.swift:2501-2514`).
- A heavy haptic fires, then 0.5 s later the action (`SlideToConfirmView.swift:223-235`), then the toast "Slept …" with Undo.
- A sleep under a minute is discarded.

**Feedback today on start**
- Medium haptic before the write; no sound.
- Toast with Undo for 3 s, sliding up with a 0.3 s spring (`LoggedToast.swift:70-83`).
- Tile-to-card swap on a spring (0.45, 0.8) (`HomeView.swift:430`; transitions at 414 and `LogButtons.swift:91`).
- The Today card's sleep total pops to 1.12 for 0.45 s, and its glow dot and caption start breathing (`TodayHeroCard.swift:405-407, 533-538, 1249-1265`).
- The system island lengthens.

**Hook for the bedtime moment**
- Inside `HomeView.startSleep()` after the guard (2489). This is the only by-hand-on-Home path.
- Other paths never pass through it, and reach Home only as an `@Query` change:
  - Siri, widgets and controls: `QuickLogger.toggleSleep` (`TwoOfUs/Intents/ToggleSleepIntent.swift:41, 81, 112, 154`);
  - SNOO: `SnooSuggestionCard.swift:185`, `TwoOfUs/SNOO/SnooSyncCoordinator.swift:410`;
  - CloudKit.
- Precedent for reacting to those: the animation keyed to `active != nil` (`HomeView.swift:428-431, 2884-2896`).
- The same `startSleep` is reached from iPad, tall and short layouts (1559-1563), which have no sky.

**While he sleeps, Home does not dim.** The sky takes no sleep input (`SkyBackground.swift:40-58`). `CradleField`, which dims the room and lights the hinge, is drawn only behind the other tabs' spreads (`SpreadScaffold.swift:125, 221-250`). On Home only the cards change.

## 5. How Home animates, and Reduce Motion

- **Implicit animations keyed to state** (`HomeView.swift:430-435, 2884-2896`), plus view transitions at 414, 1566, `LogButtons.swift:91`, `TodayHeroCard.swift:376, 661`, `LoggedToast.swift:70`.
- **`withAnimation`** appears only at `HomeView.swift:1655`, `LoggedToast.swift:79` and `SleepActiveCard.swift:249`.
- **Loops:** `repeatForever` breathing in the Today card; three shimmer passes on the slide (`SlideToConfirmView.swift:124-127`).
- **Not used anywhere in Home:** keyframes, phase animators, matched geometry, shaders. The one `Canvas` is the day strip (`TodayHeroCard.swift:1166`).
- **Fold open/close and rotation:** no animation.

**Launch curtain** (`TwoOfUs/App/LaunchOverlay.swift`)
- Opaque, above everything, blocks touches (137-141).
- Cold launch holds 0.9–3.0 s; resume after 30 minutes or more in the background holds 0.6–2.5 s (152-181; `RootView.swift:51-58, 175-196`).
- Then a 0.5 s dissolve (238-250). A widget deep link skips it (153-159).
- Home and its sky are mounted and running underneath. `launchDone` is private to `RootView` (29), so Home cannot tell it is covered.

**Reduce Motion**
- Handled per site by `reduceMotion ? nil : animation` and `.opacity` transitions. There is no shared helper.
- Sites: `HomeView.swift:430, 434`; `LogButtons.swift:250-251`; `LoggedToast.swift:70, 83`; `TodayHeroCard.swift:518, 533-537, 573, 1256-1264`; `SkyBackground.swift:375-381` (stars held still); `LaunchOverlay.swift:199-210, 239-243`.
- Not gated: the slide's arrival springs, and the three `withAnimation` calls above.

## 6. What Home observes, and cost

- **17 `@Query` arrays with no date limit** (`HomeView.swift:12-46`). Any insert or sync re-runs the whole body.
- **`@State` holding `@Observable` singletons** (58-63): `LocalPrefs`, `SetupProgress`, `DeepLinkRouter`, `SnooSyncCoordinator`, `BrightwheelManager`, `DaycareGeofenceManager`.
- **Environment:** size classes, `scenePhase`, Reduce Motion (6-10). Also `toast`, sheet states, and `dayStart` at midnight (93, 1662-1670).
- **The cards row re-evaluates every second** (386). Each tick recomputes, on the main thread:
  - `todaySummary` (1889-1900), `todayMarks` (1726-1741), `daycareAttendance` (1810-1817);
  - `feedHint` (1953-1994), `sleepHint`, `sleepTarget` (2084-2096), `nightState` (2103-2107).
  - Several of these map all feeds or all sleeps. The visible text changes only once a minute.
- The leading page re-evaluates once a minute (641).
- **Costly for a 60 fps sky behind it:**
  - the two to four live Liquid Glass surfaces (tiles, sleep card, slide) plus the system tab bar, all sampling what is behind them;
  - the 1 Hz main-thread burst;
  - two full sky views on the spread.
- Home has no `Material` or blur. The current sky has seven blurred layers repainted once a minute, and a 24 fps star timeline of shadowed circles at night (`SkyBackground.swift:340, 358, 378-412`).
- Not measured; these are risks read from the code.

## 7. Surprising or fragile

1. **`docs/IPHONE_DUO.md` is out of date for Home.**
   - It names `HomeView.spread` and `phonePageFrame` (lines 74, 128), a Sleep-tile-sized card and a "bloom" on the cover (316-320), and the room dimming on Home (305-306).
   - In the code, `footprint:` is never passed true and Home draws no `CradleField`.
   - `condensedCaption` (`HomeView.swift:408, 1478`) is a dead parameter; its doc comment is orphaned at `TodayHeroCard.swift:116-121`.
2. **Strip on the leading side.** The phone turned round while open is handled by layout (`TwoOfUsTests/PhonePageTests.swift:12-16, 44-48`). The phone-page sky is then 382 pt wide at x 569, not 466. The lab assumes the strip trails.
3. **Demo mode.** The pill row sits above Home (`RootView.swift:97-102`), so the sky cannot reach the display's top and its origin shifts down.
4. **Dynamic Type** (hero type scales to 1.6×, `TwoOfUs/DesignSystem/Typography.swift:42-45`) and name length move every header and card frame.
5. **The spread is 669 pt tall against the cover's 678.** Everything is laid out from the top (`docs/IPHONE_DUO.md:74`).
6. **Fading cards.** Hero, tiles and sleep card are one list row; the timeline is many rows with card-piece backgrounds. An `.opacity` on the List must go before `.background` (460-461) or it fades the sky. Glass under fractional opacity is untested.
7. **Toast against caption.** "Started sleep · Undo" occupies the list's foot for 3 s from the tap; the moment's caption stands at the foot from 2.0 to 4.6 s. Undo during the moment soft-deletes the sleep, which un-begins the night; no transition is designed for that.
8. **Edits change the log after the fact.** `SleepStartEditSheet` (`HomeView.swift:252-256`) and `resumeSleep` (`EventStore.swift:545-558`) both do.
9. **"Night" has three meanings in the app; the sky's 6 pm–4 am would be a fourth.**
   - `SleepLanguage`: 8 PM–6 AM by start hour (`TwoOfUs/Store/SleepLanguage.swift:16-31`).
   - The adjustable night window: default 20:00–08:00 (`HomeView.swift:778-779`).
   - The leading page's own moments (683-691).
10. **Home cannot tell it is on screen.** Tab selection is private to `MainTabView` (`RootView.swift:310`) and the curtain state is private. The resume curtain is likely to coincide with opening the Duo after a long gap.
11. **Demo toggle** rebuilds the whole tree (`TwoOfUs/App/TwoOfUsApp.swift:162-166`), resetting any moment state.
12. **`SkyBackground` ignores Low Power Mode;** `CradleField` honours it (`TwoOfUs/DesignSystem/CradleField.swift:94-96`).
13. **A Split View half beside the strip is taken for the cover** (`docs/IPHONE_DUO.md:312-320`).

## What I read and did not read

**Read in full**
- `TwoOfUs/Features/Home/`: `HomeView.swift`, `LogButtons.swift`, `TodayHeroCard.swift`, `SpreadDetailViews.swift`, `LoggedToast.swift`, `DropoffBoardSheet.swift`.
- `docs/IPHONE_DUO.md`.
- `TwoOfUs/Features/Shared/`: `PaneLayout.swift`, `PhonePage.swift`, `SpreadGrid.swift`, `SpreadSpine.swift`, `SpreadScaffold.swift`, `PageTitle.swift`, `SlideToConfirmView.swift`, `Avatar.swift`.
- `TwoOfUs/App/`: `RootView.swift`, `LaunchOverlay.swift`, `TwoOfUsApp.swift`, `OrientationPolicy.swift`.
- `TwoOfUs/DesignSystem/`: `Colors.swift`, `Typography.swift`, `Haptics.swift`.
- `TwoOfUs/Features/Sleep/SleepActiveCard.swift`.
- `TwoOfUsTests/`: `PhonePageTests.swift`, `SpreadGridTests.swift`, `SpreadSpineTests.swift`.

**Read in part**
- `SkyBackground.swift` (not the colour keyframes or the moon and ridge tables, about lines 600–695 and 770–895).
- `CradleField.swift` 1–200; `EventStore.swift` 440–570; `SleepLanguage.swift` 1–80; `TwoOfUsWidgets/SleepLiveActivityView.swift` 360–455.
- `design/sky-lab/BRIEF.md` 186–443.
- In the worktree `design/sky-lab/`: `skies/hill-painted.md` (the "SwiftUI port" section only), `skies/hill-painted.js` 100–330, `lab/core.js` and `lab/chrome.js` (layout tables only).

**Not read**
- `AppDelegate.swift`; `ScheduleView`, `HistoryView`, `StatsView` (grep only); `JournalCard`; the timeline row views; `SleepActivityManager`; `QuickLogger`; `SolarClock`; `MoonClock`.
- `lab/presence.js`, `air.js`, `tree.js`, the lab README.
- The other test files.
