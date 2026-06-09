import SwiftUI

/// The signature Home visual: the day rendered as a sunrise-to-night **arc**.
///
/// The dome sweeps midnight → noon (top) → midnight across the width. A faint
/// track shows the whole day; a gradient overlay fills the part of the day that
/// has already happened, led by a glowing "now" orb that is *warm* in daylight
/// and *cool* at night. Feeds and diapers sit as marks on the arc; sleep stretches
/// render as soft periwinkle bands riding just inside it.
///
/// This reuses `RibbonMark` (same data the flat ribbon and widgets consume), so
/// nothing about the event model changes — only how today is drawn.
struct DayArcView: View {
    let marks: [RibbonMark]
    var day: Date = .now
    var now: Date = .now

    private let cal = Calendar.current

    var body: some View {
        Canvas { ctx, size in
            let pad: CGFloat = 16
            let cx = size.width / 2
            let baseY = size.height - pad
            let rx = (size.width - pad * 2) / 2
            let ry = size.height - pad * 2

            // t (0…1) → point on the dome. θ runs π (left) → 0 (right).
            func point(_ t: CGFloat) -> CGPoint {
                let theta = CGFloat.pi - max(0, min(1, t)) * .pi
                return CGPoint(x: cx + cos(theta) * rx, y: baseY - sin(theta) * ry)
            }
            func arcPath(from a: CGFloat, to b: CGFloat) -> Path {
                var p = Path()
                let steps = 64
                let lo = min(a, b), hi = max(a, b)
                for i in 0...steps {
                    let t = lo + (hi - lo) * CGFloat(i) / CGFloat(steps)
                    let pt = point(t)
                    if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                }
                return p
            }

            let dayStart = cal.startOfDay(for: day)
            func frac(_ date: Date) -> CGFloat {
                CGFloat(max(0, min(1, date.timeIntervalSince(dayStart) / 86_400)))
            }
            let nowT = cal.isDate(day, inSameDayAs: now) ? frac(now) : 1

            // 1. Full-day track (faint).
            ctx.stroke(arcPath(from: 0, to: 1),
                       with: .color(AppColor.separator.opacity(0.6)),
                       style: StrokeStyle(lineWidth: 3, lineCap: .round))

            // 2. Elapsed portion — dawn→day gradient up to "now".
            if nowT > 0.001 {
                ctx.stroke(
                    arcPath(from: 0, to: nowT),
                    with: .linearGradient(
                        Gradient(colors: [
                            AppColor.accentSleep.opacity(0.5),  // pre-dawn
                            AppColor.accentFeed,                // midday
                            arcNowColor.opacity(0.9),           // toward now
                        ]),
                        startPoint: point(0), endPoint: point(nowT)
                    ),
                    style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                )
            }

            // 3. Sleep bands — ride just inside the arc.
            for mark in marks where mark.kind == .sleep {
                let a = frac(mark.start)
                let b = frac(mark.end ?? now)
                guard b > a else { continue }
                ctx.stroke(
                    insetArc(from: a, to: b, point: point, inset: 7),
                    with: .color(AppColor.accentSleep.opacity(0.9)),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
            }

            // 4. Feed dots + diaper rings on the arc.
            for mark in marks where mark.kind != .sleep {
                let pt = point(frac(mark.start))
                let r: CGFloat = 4
                let rect = CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)
                if mark.kind == .diaper {
                    ctx.stroke(Path(ellipseIn: rect),
                               with: .color(AppColor.accentDiaper), lineWidth: 2)
                } else {
                    ctx.fill(Path(ellipseIn: rect), with: .color(AppColor.accentFeed))
                }
            }

            // 5. The "now" orb — warm in daylight, cool at night, with a soft glow.
            if cal.isDate(day, inSameDayAs: now) {
                let pt = point(nowT)
                let glow = CGRect(x: pt.x - 11, y: pt.y - 11, width: 22, height: 22)
                ctx.fill(Path(ellipseIn: glow), with: .color(arcNowColor.opacity(0.22)))
                let orb = CGRect(x: pt.x - 5, y: pt.y - 5, width: 10, height: 10)
                ctx.fill(Path(ellipseIn: orb), with: .color(arcNowColor))
                ctx.stroke(Path(ellipseIn: orb), with: .color(.white.opacity(0.85)), lineWidth: 1.5)
            }
        }
        .accessibilityHidden(true)
    }

    /// An arc segment drawn at a slightly smaller radius (visually inside the dome).
    private func insetArc(from a: CGFloat, to b: CGFloat,
                          point: (CGFloat) -> CGPoint, inset: CGFloat) -> Path {
        // Approximate inset by nudging each sampled point toward the baseline center.
        var p = Path()
        let steps = 48
        let lo = min(a, b), hi = max(a, b)
        for i in 0...steps {
            let t = lo + (hi - lo) * CGFloat(i) / CGFloat(steps)
            let pt = point(t)
            let nudged = CGPoint(x: pt.x, y: pt.y + inset)
            if i == 0 { p.move(to: nudged) } else { p.addLine(to: nudged) }
        }
        return p
    }

    /// Warm amber by day (6–18), cool periwinkle at night — a quiet nod to the
    /// time you're holding the phone, without a full palette shift.
    private var arcNowColor: Color {
        let hour = cal.component(.hour, from: now)
        return (hour >= 6 && hour < 18) ? AppColor.accentDiaper : AppColor.accentSleep
    }
}
