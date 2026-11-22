import SwiftUI

/// The tall sky's plane, printed by `SkyField.metal` from a
/// `SkyFieldTexture`: as wide as the world this display can see and as tall
/// as the looked-up view needs. The hush (`presence`) and the room's `depth`
/// are the shader's uniforms, so a change of tone costs no new texture.
struct SkyField: View {
    let texture: SkyFieldTexture
    let minute: SkyBenchMinute
    var presence: Double
    var depth: Double
    /// A probe of the shader's own plumbing, for the bench (0: the sky).
    var probe: Int = 0

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let air = minute.air
        let world = minute.world
        let dark = air.dark
        Rectangle()
            .fill(.black)
            .frame(width: texture.size.width, height: texture.size.height)
            .colorEffect(ShaderLibrary.skyField(
                .image(Image(decorative: texture.image, scale: 1)),
                .float2(CGFloat(texture.columns), CGFloat(texture.rows)),
                .float4(presence, depth, dark ? 1 : 0, air.toward),
                .float4(SkyMath.lerp(0.2, 0.62, air.night),
                        dark ? 0.011 : 0.007,
                        air.night,
                        dark ? 0.013 * air.night * (1 - 0.8 * air.moonlight) : 0),
                .float4(Double(world.horizon) - Double(texture.origin.y),
                        Double(world.skySpan),
                        Double(world.tree.x) - Double(texture.origin.x),
                        Double(world.tree.height)),
                .float2(displayScale, CGFloat(probe))))
    }
}
