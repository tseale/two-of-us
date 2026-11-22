import Foundation

/// What the sky plays when tonight changes — chosen by `SkyScript`, played
/// by the driver. Looking up is a state, not a moment; these are the only
/// ways between its two poses.
///
/// Each event carries the camera's `look` by one `Move`, and every curve
/// `look` ever follows is written here once: the moment's own table reads
/// its rise through `Move.bedtime`, and the quiet events' samples
/// (`Moment.arrive`, `Moment.settle`) through `Move.arrive` and
/// `Move.settle`. Tested in `SkyEventTests`, against `look` as the sky
/// lab's own page plays each event.
enum SkyEvent: Equatable {
    /// The bedtime moment: a night sleep started by hand on this phone's
    /// Home, and the night begins with it. The cards fall back, the view
    /// rises, tonight's star is lit, the band crosses, "✦ Night N" stands at
    /// the foot, and the cards return over the sky that is already there.
    /// Once a night. Everything but the rise is the moment's own table
    /// (`Moment.frame`).
    case bedtime
    /// The night begins any other way while Home is on screen, just now:
    /// the quiet rise, behind the cards. No veil, no band, no caption.
    case arrive
    /// First light — or the night un-begun by an undo or a delete: the quiet
    /// settle back to the hill, behind the cards, as tonight's star goes out.
    case settle
    /// No move at all: the pose Home should already be in dissolves in. For
    /// a night that turns out to have begun a while ago (a late sync, a
    /// backdated SNOO sleep), or a morning found long after first light.
    case dissolve(lookingUp: Bool)

    // MARK: The camera's move

    /// How an event carries `look` (0 on the hill … 1 looking up).
    struct Move: Equatable {
        let target: Double
        /// Held where it is for this long first.
        let delay: TimeInterval
        let duration: TimeInterval
        let curve: Glide.Curve

        /// `look` `age` seconds into the event, for a view that stood at
        /// `start` when it began: held for `delay`, then eased to the
        /// target, and there from `delay + duration` on.
        func look(age: TimeInterval, from start: Double) -> Double {
            Glide.value(from: start, to: target, elapsed: age - delay, duration: duration, curve: curve)
        }

        /// The bedtime moment's rise, as the moment's table has it
        /// (`Moment.beats`): from 0.3 s, once the cards have begun to go,
        /// up by 2.4 s on the Duo and by 2.7 s on the slab, whose sky is
        /// twice as tall. Under Reduce Motion there is no move: the
        /// looked-up still dissolves in once the cards are away.
        static func bedtime(world: SkyWorld.Kind, reduced: Bool) -> Move {
            let rise = Moment.beats(world: world, reduced: reduced).rise
            return Move(target: 1, delay: rise.lowerBound, duration: rise.upperBound - rise.lowerBound,
                        curve: reduced ? .smoothstep : .quintic)
        }

        /// The quiet rise: up over 2.5 s on the camera's quintic
        /// (skies/hill-painted.js, `lookOf`). Under Reduce Motion: the
        /// dissolve.
        static func arrive(reduced: Bool) -> Move {
            reduced ? Move.dissolve(lookingUp: true) : Move(target: 1, delay: 0, duration: 2.5, curve: .quintic)
        }

        /// The quiet settle: it holds a tenth of a second and is down by
        /// 2.7 s, on the camera's quintic. Under Reduce Motion: the
        /// dissolve.
        static func settle(reduced: Bool) -> Move {
            reduced ? Move.dissolve(lookingUp: false) : Move(target: 0, delay: 0.1, duration: 2.6, curve: .quintic)
        }

        /// No move: `look` is the weight of the looked-up still in a short
        /// cross-fade, with or without motion.
        static func dissolve(lookingUp: Bool) -> Move {
            Move(target: lookingUp ? 1 : 0, delay: 0, duration: SkyEvent.dissolveDuration, curve: .smoothstep)
        }
    }

    /// A dissolve's length, and every quiet event's under Reduce Motion
    /// (lab/presence.js, `MOMENT.quiet.dissolve`): "not the camera's curve —
    /// a two-second dissolve is two trees on screen for two seconds".
    static let dissolveDuration: TimeInterval = 0.6

    /// The camera's move for this event. `world` matters to `bedtime`
    /// alone (its rise keeps the pace of the world's size); `reduced` is
    /// Reduce Motion, under which no event moves the camera and `look` is
    /// the weight of the looked-up still in a dissolve.
    func move(world: SkyWorld.Kind, reduced: Bool) -> Move {
        switch self {
        case .bedtime: return .bedtime(world: world, reduced: reduced)
        case .arrive: return .arrive(reduced: reduced)
        case .settle: return .settle(reduced: reduced)
        case .dissolve(let lookingUp): return .dissolve(lookingUp: lookingUp)
        }
    }

    /// `look` after this event starts at `now`: the glide it had, given the
    /// event's target from wherever it is — so an event during another
    /// eases from where the view has got to (an Undo in the middle of the
    /// bedtime rise settles from there, not from the top), and one that
    /// asks for the pose the view is already bound for changes nothing.
    func carrying(_ look: Glide, at now: Date, world: SkyWorld.Kind, reduced: Bool) -> Glide {
        let move = move(world: world, reduced: reduced)
        return look.retargeted(to: move.target, at: now, over: move.duration, after: move.delay,
                               curve: move.curve)
    }
}
