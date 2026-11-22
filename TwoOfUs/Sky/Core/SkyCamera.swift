import Foundation

/// The camera of the painted hill. It has two poses — at rest, the everyday
/// view of the hill, and looking up, the night's view into every night of his
/// life — and one number between them, the `look`: 0 at rest, 1 looking up.
///
/// Looking up is only a slide. Every plane of the picture TRANSLATES — the
/// far ones with the sky, the near ones faster — and nothing is repainted for
/// the move: this type says how far each kept image is offset for a look, and
/// the few things that follow the look alone (tonight's star between its two
/// homes, the tree, the clouds).
///
/// Pure, and the sky lab's rules to the number (`hill-painted.js`:
/// `planeOffset`, `onGrid`, `tonightHome`, `onTheWay`, `treeShown`): pinned
/// against offsets exported from the lab's page in `SkyCameraTests`.
enum SkyCamera {
    // MARK: The planes

    /// A plane's whole travel between the two poses, in points: left by its
    /// share of the world's turn and down by its share of the drop — each
    /// rounded to WHOLE DEVICE PIXELS at `scale`, so a plane comes to rest on
    /// the pixel grid. The near planes' true travel is not on it (349.44 and
    /// 405.6 pt down on the Duo; a third-point grid has neither), and a layer
    /// left there sits resampled — soft — all night: 349.44 becomes 349.5 at
    /// 2×. The last frame of a move is then the standing frame, not a soft one.
    static func travel(of plane: SkyWorld.Plane, scale: Double, world: SkyWorld) -> CGSize {
        let pixels = pixelsPerPoint(scale)
        let left = roundedHalfUp(world.turn * plane.slide * pixels) / pixels
        let down = roundedHalfUp(world.drop * plane.sink * pixels) / pixels
        return CGSize(width: -left, height: down)
    }

    /// Where a plane's rest-pose picture sits for this pose: its `.offset`,
    /// in points.
    ///
    /// - `look`: 0 at rest … 1 looking up. The move runs between the two
    ///   resting offsets, which are whole device pixels; on the way the
    ///   plane travels between pixels (an offset rounded in every frame holds
    ///   for a frame and then nudges at the slow ends of the move).
    /// - `tilt`: the phone's tilt, −1 … 1 on each axis, for parallax (each
    ///   plane has its own reach; the sky leans the other way). Not built in
    ///   the first version: pass `.zero`. A tilt is taken to the pixel grid
    ///   too, so a plane at rest is never between pixels.
    /// - `scale`: device pixels per point.
    ///
    /// With no tilt this is the lab's offset exactly, at every look. Under a
    /// tilt the lab leaves the tilt's fraction of a pixel in while the camera
    /// moves and rounds it away at either pose — a step of up to half a pixel
    /// in the move's first and last frame; here the move runs between the two
    /// rounded offsets, as the lab's port notes ask, so no join jumps.
    static func offset(of plane: SkyWorld.Plane, look: Double, tilt: CGSize = .zero,
                       scale: Double, world: SkyWorld) -> CGSize {
        let pixels = pixelsPerPoint(scale)
        let whole = travel(of: plane, scale: scale, world: world)
        let lean = leaning(plane, tilt)
        let restX = roundedHalfUp(lean.width * pixels) / pixels
        let restY = roundedHalfUp(lean.height * pixels) / pixels
        let up = CGFloat(SkyMath.clamped(look))
        return CGSize(width: restX + whole.width * up, height: restY + whole.height * up)
    }

    // MARK: Tonight's star

    /// Tonight's star is on no plane. It has two homes on the display — above
    /// the tree's left shoulder at rest, in the clear window looking up — and
    /// goes from one to the other in a straight line with the camera, so it
    /// is still wherever the view comes to rest. Display points; `anchorX` is
    /// where the anchor window begins on this display (485 on the spread).
    ///
    /// At rest it rides the knoll, where the tree is, and looking up it rides
    /// the sky: under a tilt each home leans as its plane does.
    static func tonightHome(look: Double, tilt: CGSize = .zero, world: SkyWorld,
                            anchorX: CGFloat = 0) -> CGPoint {
        let knoll = leaning(world.plane(.knoll), tilt)
        let sky = leaning(world.sky, tilt)
        let restX = anchorX + world.tonight.x + knoll.width
        let restY = world.tonight.y + knoll.height
        let upX = anchorX + world.tonightUp.x + sky.width
        let upY = world.tonightUp.y + sky.height
        let up = CGFloat(look)
        return CGPoint(x: restX + (upX - restX) * up, y: restY + (upY - restY) * up)
    }

    // MARK: What follows the look

    /// Is the view on its way between the poses? 0 at rest and up, 1 between:
    /// a smooth gate for what belongs only to the move (the sun's disc gives
    /// way beside tonight's star as the star crosses the field; the edge his
    /// sky keeps at the fold is soft only while a star may cross it).
    static func onTheWay(_ look: Double) -> Double {
        SkyMath.smoothstep(0, 0.08, look) * (1 - SkyMath.smoothstep(0.92, 1, look))
    }

    /// How much of the tree is drawn, 0 … 1. THE TREE IS A LAYER OF ITS OWN,
    /// and with the cards on, looking up, it is not drawn at all: the night's
    /// subject with the cards on is tonight's star among his stars, and the
    /// tree is what the cards uncover at bedtime. All of it at rest, and
    /// looking up with the cards away (the bare poster of the bedtime
    /// moment); it goes with the cards' return, leaves early in a rise behind
    /// the cards and comes back over the last of the way down at first light.
    ///
    /// `cards`: the opacity of the phone page's own cards (not the header's
    /// words, the strip, the tab capsule or the undo toast, which stay).
    static func treeShown(look: Double, cards: Double) -> Double {
        1 - SkyMath.smoothstep(0.05, 0.45, look) * SkyMath.clamped(cards)
    }

    /// How much of a cloud is there for a look, 0 … 1, by the view it belongs
    /// to: the everyday view's own leave as the camera looks up — nothing
    /// stands among his stars — and the looked-up view's own arrives with it.
    static func cloudShown(_ belongs: SkyWorld.Cloud.Belongs, look: Double) -> Double {
        switch belongs {
        case .rest: return 1 - SkyMath.smoothstep(0.1, 0.55, look)
        case .up: return SkyMath.smoothstep(0.35, 0.85, look)
        case .always: return 1
        }
    }

    // MARK: Helpers

    /// How far a tilt leans a plane, in points (the tilt is held to ±1).
    private static func leaning(_ plane: SkyWorld.Plane, _ tilt: CGSize) -> CGSize {
        let x = min(1, max(-1, tilt.width))
        let y = min(1, max(-1, tilt.height))
        return CGSize(width: x * plane.tilt.width, height: y * plane.tilt.height)
    }

    /// Device pixels per point; a scale that is not one (zero, before a
    /// display is known) is taken as 1.
    private static func pixelsPerPoint(_ scale: Double) -> CGFloat {
        scale > 0 ? CGFloat(scale) : 1
    }

    /// To the nearest whole number, a half going up — the lab's rounding
    /// (`SkyMath.round`), which Swift's `.rounded()` is not for a negative
    /// half.
    private static func roundedHalfUp(_ value: CGFloat) -> CGFloat {
        CGFloat(SkyMath.round(Double(value)))
    }
}
