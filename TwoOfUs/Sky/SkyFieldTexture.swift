import CoreGraphics
import Foundation

/// The sky field's negative: the air sampled on the lab's 2-point grid, in
/// OKLab, BEFORE the room's tone — the sun's own glow and its warm column
/// laid in, the hush and the dimming left out. `SkyField.metal` prints it:
/// the tone arrives there as uniforms, ahead of the dither, so an event can
/// change it every frame without a new texture (`paintSky` in
/// hill-painted.js; its notes' port note 10).
///
/// One 16-bit image carries both halves: the colour above (lightness, a +
/// ½, b + ½) and, under a gutter, the brush's drag (+ ½), whose strength
/// follows the hush and so cannot be baked into the colour.
struct SkyFieldTexture {
    /// The grid's step, in points.
    static let step = 2.0
    /// Rows left between the two halves, so a sample never reads across.
    static let gutter = 2

    let image: CGImage
    /// Samples across, and down one half.
    let columns: Int
    let rows: Int
    /// The plane it covers, in points.
    let size: CGSize
    /// World x of the plane's leading edge, and rest-pose y of its top.
    let origin: CGPoint

    /// The texture for one minute. Nil if its buffer or its image cannot be
    /// had, or if the task making it is cancelled before its last row.
    static func make(for minute: SkyBenchMinute) -> SkyFieldTexture? {
        let world = minute.world
        let air = minute.air
        let anchorWidth = Double(minute.display.anchorWidth)
        let table = Double(world.skySpan)
        let horizon = Double(world.horizon)
        let left = minute.planeLeading
        let top = Double(world.skyTop)
        let width = minute.planeTrailing - left
        let height = Double(world.skyFoot) - top
        let columns = Int((width / step).rounded(.up)) + 2
        let rows = Int((height / step).rounded(.up)) + 2
        let tall = rows * 2 + gutter

        let sunX = minute.sunX
        let sunY = minute.sunSkyY
        let glow = air.glow
        let glowAmount = air.glowAmount
        let altitude = minute.sunAltitude
        // A sun still a hand above the horizon stands in a wide warm column
        // of its own light; nothing of it below 2.5°.
        let column = (air.dark ? 0.62 : 0.3) * glowAmount * SkyMath.smoothstep(2.5, 6, altitude)
            * (1 - SkyMath.smoothstep(11, 17, altitude))

        // The samples are written straight into the one buffer the image will
        // own. (Build 234 filled an array and copied it into a `Data`, and
        // trapped there when memory for the copy could not be had.) A buffer
        // that cannot be had ends the texture here, with no picture.
        let count = columns * tall * 4
        let bytes = count * MemoryLayout<UInt16>.stride
        guard let memory = calloc(count, MemoryLayout<UInt16>.stride) else { return nil }
        // From here `data` owns the buffer, and frees it on every way out.
        let data = Data(bytesNoCopy: memory, count: bytes, deallocator: .free)
        let samples = memory.bindMemory(to: UInt16.self, capacity: count)
        func store(_ value: Double, at index: Int) {
            samples[index] = UInt16((SkyMath.clamped(value) * 65_535).rounded())
        }
        for row in 0..<rows {
            // A texture nobody is waiting for any more stops here.
            guard !Task.isCancelled else { return nil }
            let y = top + Double(row) * step
            let elevation = (horizon - y) / table
            let shape = 0.5 + 0.5 * SkyMath.smoothstep(-0.1, 0.5, elevation)
            for columnIndex in 0..<columns {
                let x = left + Double(columnIndex) * step
                var colour = air.sky(dx: (x - sunX) / anchorWidth, elevation: elevation)
                if glowAmount > 0.004 {
                    let reach = SkyMath.hypot((x - sunX) / table * 0.8, (y - sunY) / table * 1.2)
                    let share = min(0.92, glowAmount * (0.60 * exp(-reach / 0.27) + 0.45 * exp(-reach / 0.07)))
                    colour = colour.mixed(with: glow, by: share)
                }
                if column > 0.004 {
                    let reach = SkyMath.hypot((x - sunX) / table * 0.62, (y - sunY) / table * 0.5)
                    let share = min(0.8, column * exp(-reach * reach / 0.36)
                        * (0.55 + 0.45 * SkyMath.smoothstep(-0.05, 0.5, elevation)))
                    colour = colour.mixed(with: OKLab(lightness: glow.lightness + 0.02, a: glow.a, b: glow.b),
                                          by: share)
                }
                let drag = SkyNoise.drift(x / 120 + 3.1, y / 9 + (x - sunX) * 0.004 + 1.7, octaves: 3) - 0.5
                let colourAt = (row * columns + columnIndex) * 4
                store(colour.lightness, at: colourAt)
                store(colour.a + 0.5, at: colourAt + 1)
                store(colour.b + 0.5, at: colourAt + 2)
                samples[colourAt + 3] = .max
                let dragAt = ((rows + gutter + row) * columns + columnIndex) * 4
                store(drag * shape + 0.5, at: dragAt)
                samples[dragAt + 3] = .max
            }
        }

        guard let provider = CGDataProvider(data: data as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue
            | CGBitmapInfo.byteOrder16Little.rawValue)
        guard let image = CGImage(width: columns, height: tall, bitsPerComponent: 16, bitsPerPixel: 64,
                                  bytesPerRow: columns * 8, space: space, bitmapInfo: info,
                                  provider: provider, decode: nil, shouldInterpolate: false,
                                  intent: .defaultIntent) else { return nil }
        return SkyFieldTexture(image: image, columns: columns, rows: rows,
                               size: CGSize(width: width, height: height),
                               origin: CGPoint(x: left, y: top))
    }
}
