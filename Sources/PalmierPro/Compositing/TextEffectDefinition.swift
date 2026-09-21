import Foundation

struct TextEffectDefinition: Codable, Sendable {
    let fill: TextStyle.RGBA
    let outlines: [TextStyle.GlyphOutline]

    func validate() throws {
        let colors = [fill] + outlines.map(\.color)
        guard outlines.count <= 8, colors.allSatisfy({ c in
            [c.r, c.g, c.b, c.a].allSatisfy { $0.isFinite && (0...1).contains($0) }
        }), fill.a == 1, outlines.allSatisfy({ layer in
            layer.widthEm.isFinite && (0...1).contains(layer.widthEm) &&
            layer.xEm.isFinite && abs(layer.xEm) <= 1 && layer.yEm.isFinite && abs(layer.yEm) <= 1
        }) else { throw LUTStoreError.invalid("Invalid text decoration") }
    }

    func apply(to style: inout TextStyle) {
        style.color = fill
        style.border.enabled = false
        style.decoration = outlines
    }
}
