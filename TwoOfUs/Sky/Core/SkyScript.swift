import Foundation

/// This phone's own tap on Home's Sleep button, remembered for a few
/// seconds: the one thing that tells "started by hand, here, just now" from
/// a sleep that arrived by sync, Siri, a widget or SNOO (their records are
/// identical). Held in memory by the driver, never stored and never synced.
struct HandStart: Equatable {
    /// The sleep the tap made — kept so that Undo of THAT sleep can be told
    /// (`undoneAt`), not to decide what plays.
    let sleepID: UUID
    /// When Home's button was tapped.
    let at: Date
    /// When the toast's Undo took it back, if it did.
    var undoneAt: Date?
}

/// Which event a change of tonight plays: the sky's stage directions.
///
/// It keys on ONE derived fact — the night has begun (`NightState.hasBegun`)
/// — and never on a sleep's id: editing a sleep replaces its row under a new
/// id, a sync can deliver a start and its stop as one change, and two phones
/// can each open a sleep. None of those is the night beginning.
///
/// The rules, in the order they are tried:
/// 1. The first evaluation after Home appears or becomes active plays
///    nothing: Home is simply in the right pose.
/// 2. The night begins with this phone's hand token fresh, and the moment
///    has not played tonight: `bedtime`.
/// 3. The night begins any other way: `arrive` if the sleep that began it is
///    still running and started within 90 s of now (a start ahead of this
///    clock counts as now); otherwise the 0.6 s dissolve.
/// 4. First light: `settle` — if Home is there for it. Found more than five
///    minutes late, the hill simply dissolves in.
/// 5. The night un-begun any other way (an undo, a delete, an edit): hold
///    for 1.5 s, then `settle` if it is still un-begun. An edit is a delete
///    and an insert that can land in two batches; held, it plays nothing.
///    This phone's own Undo skips the hold.
/// 6. Nothing else moves the sky: not a wake, not a feed, not a second sleep
///    the same night, not midnight.
/// 7. The moment plays once a night, and is spent only once its caption is
///    up (2.8 s by the moment's table): a mis-tap undone at once does not
///    spend it; undone later, a second tap rises quietly.
///
/// Pure: the driver keeps the `Standing` each step hands back and plays the
/// event it names; it has no rules of its own. Tested in `SkyScriptTests`.
enum SkyScript {
    // MARK: The numbers

    /// How long a hand token (and its Undo) stays fresh.
    static let handTokenLife: TimeInterval = 5
    /// How recently the night's sleep must have started for its arrival to
    /// be worth a rise. Older than this it did not "just" begin: a late
    /// sync, a backdated SNOO sleep, the fetch that lands after Home opens.
    static let arrivalWindow: TimeInterval = 90
    /// How long an un-beginning waits to see whether it is one.
    static let unbeginHold: TimeInterval = 1.5
    /// How long after first light a settle is still first light's. The lab
    /// plays `settle` only while the sun is within half a degree of −7°
    /// (three to five minutes): "first light is a minute, not the whole
    /// morning".
    static let firstLightWindow: TimeInterval = 5 * 60
    // MARK: What the driver keeps

    /// Where the script left the sky: the night it last acted on, and
    /// whether it is waiting to see if an un-beginning is real.
    struct Standing: Equatable {
        /// The state the sky is showing. While a hold runs this is still
        /// the begun night: the view has not come down.
        let night: NightState
        /// When the night was first seen un-begun, while the hold runs.
        let unbegunSince: Date?
    }

    /// One step's outcome.
    struct Step: Equatable {
        /// What to play now, if anything.
        let event: SkyEvent?
        /// What to hand back as `from` next time.
        let standing: Standing
        /// While a hold runs: when to ask again, with the state as it then
        /// stands (the driver's minute tick is far too slow for it).
        let askAgainAt: Date?
    }

    // MARK: The step

    /// What the change from `from` to tonight's state `to` plays at `now`.
    /// `from` is the last step's `standing`, or nil for the first
    /// evaluation after Home appears or becomes active. `hand` is this
    /// phone's token, if one is in memory; `playedTonight` whether the
    /// moment has already been spent on this night (`hasPlayed`).
    static func step(from: Standing?, to: NightState, hand: HandStart?, playedTonight: Bool,
                     now: Date) -> Step {
        let settled = Standing(night: to, unbegunSince: nil)
        guard let from else { return Step(event: nil, standing: settled, askAgainAt: nil) }

        switch (from.night.hasBegun, to.hasBegun) {
        case (false, false), (true, true):
            // Nothing the sky moves for. (Begun again inside a hold: the
            // two halves of an edit have both landed. The hold is over.)
            return Step(event: nil, standing: settled, askAgainAt: nil)

        case (false, true):
            return Step(event: beginning(to, hand: hand, playedTonight: playedTonight, now: now),
                        standing: settled, askAgainAt: nil)

        case (true, false):
            // By the clock: the night's frame has run out.
            if let frame = from.night.frame, to.frame == nil || now >= frame.firstLight {
                let late = now.timeIntervalSince(frame.firstLight)
                let event: SkyEvent = late >= 0 && late <= firstLightWindow ? .settle : .dissolve(lookingUp: false)
                return Step(event: event, standing: settled, askAgainAt: nil)
            }
            // By the log: this phone's own Undo is certain, anything else
            // may be half of an edit.
            if let undone = hand?.undoneAt, abs(now.timeIntervalSince(undone)) <= handTokenLife {
                return Step(event: .settle, standing: settled, askAgainAt: nil)
            }
            let since = from.unbegunSince ?? now
            if now.timeIntervalSince(since) >= unbeginHold {
                return Step(event: .settle, standing: settled, askAgainAt: nil)
            }
            return Step(event: nil, standing: Standing(night: from.night, unbegunSince: since),
                        askAgainAt: since.addingTimeInterval(unbeginHold))
        }
    }

    /// What the night's beginning plays.
    private static func beginning(_ night: NightState, hand: HandStart?, playedTonight: Bool,
                                  now: Date) -> SkyEvent {
        if let hand, hand.undoneAt == nil, abs(now.timeIntervalSince(hand.at)) <= handTokenLife {
            return playedTonight ? .arrive : .bedtime
        }
        if let sleep = night.begunBy, sleep.isRunning,
           now.timeIntervalSince(sleep.start) <= arrivalWindow {
            return .arrive
        }
        return .dissolve(lookingUp: true)
    }

    // MARK: Once a night

    /// Whether the moment has been spent on the night `tonight` is in:
    /// `played` is the frame of the night it last played on, as the driver
    /// remembers it (in memory only). By day there is no tonight, and
    /// nothing has been played on it.
    static func hasPlayed(_ played: NightFrame?, tonight: NightState) -> Bool {
        guard let played, let frame = tonight.frame else { return false }
        return played.evening == frame.evening
    }

    /// Whether a moment that began `age` seconds ago has been spent: only
    /// once the caption is up, so a mis-tap undone at once leaves the night
    /// its moment. "Up" is the moment's own table's (`Moment.beats`): 2.8 s
    /// in either world, and 1.6 s under Reduce Motion, whose table is
    /// shorter.
    static func momentIsSpent(age: TimeInterval, world: SkyWorld.Kind, reduced: Bool = false) -> Bool {
        age >= Moment.beats(world: world, reduced: reduced).captionIn.upperBound
    }
}
