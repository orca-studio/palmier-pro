import CoreImage
import Foundation
import Testing
@testable import PalmierPro

struct TextDecorationTests {
    @Test func decorationPreservesEditableContentAndRoundTrips() throws {
        let definition = TextEffectDefinition(fill: .init(r: 1, g: 0.94, b: 0.336), outlines: [
            .init(color: .init(r: 1, g: 0.526, b: 0), widthEm: 0.063, xEm: -0.02, yEm: 0),
            .init(color: .init(r: 0, g: 0, b: 0), widthEm: 0.042, xEm: -0.02, yEm: 0)
        ])
        try definition.validate()
        var style = TextStyle()
        let font = style.fontName
        definition.apply(to: &style)
        #expect(style.fontName == font)
        #expect(style.glyphOutlines.count == 2)
        #expect(try JSONDecoder().decode(TextStyle.self, from: JSONEncoder().encode(style)) == style)
        var clip = Clip(mediaRef: "", mediaType: .text, startFrame: 0, durationFrames: 90)
        clip.textContent = "花字测试 ABC 123"
        clip.textStyle = style
        let image = try #require(TextFrameRenderer.image(clip: clip, frame: 0, renderSize: CGSize(width: 640, height: 360)))
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = CIContext()
        let bitmap = try #require(context.createCGImage(image, from: image.extent))
        #expect(bitmap.width > 0)
        let width = Int(image.extent.width), height = Int(image.extent.height)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        context.render(image, toBitmap: &pixels, rowBytes: width * 4, bounds: image.extent, format: .RGBA8, colorSpace: space)
        var yellow = 0, orange = 0, black = 0
        for i in stride(from: 0, to: pixels.count, by: 4) where pixels[i + 3] > 240 {
            let r = pixels[i], g = pixels[i + 1], b = pixels[i + 2]
            if r > 220 && g > 210 && b < 190 { yellow += 1 }
            if r > 220 && (90...180).contains(g) && b < 40 { orange += 1 }
            if r < 30 && g < 30 && b < 30 { black += 1 }
        }
        #expect(yellow > 20)
        #expect(orange > 20)
        #expect(black > 20)
        if let output = ProcessInfo.processInfo.environment["PALMIER_TEST_FLOWER_OUTPUT"] {
            try context.writePNGRepresentation(of: image, to: URL(fileURLWithPath: output), format: .RGBA8, colorSpace: space)
        }
        #expect(clip.textContent == "花字测试 ABC 123")
    }

    @Test func naturalSizeGrowsWithDecorationWidthAndOffset() {
        var plain = TextStyle()
        plain.color = .init(r: 1, g: 1, b: 1)
        var decorated = plain
        decorated.decoration = [.init(color: .init(), widthEm: 0.25, xEm: -0.2, yEm: 0)]
        func size(_ style: TextStyle) -> CGSize {
            TextLayout.naturalSize(content: "ABC", style: style, maxWidth: .infinity, canvasHeight: 1080)
        }
        #expect(size(decorated).width > size(plain).width)
        #expect(size(decorated).height > size(plain).height)
    }

    @Test func malformedDecorationIsRejected() {
        for width in [Double.nan, -0.1, 2] {
            let definition = TextEffectDefinition(fill: .init(), outlines: [.init(color: .init(), widthEm: width, xEm: 0, yEm: 0)])
            #expect(throws: (any Error).self) { try definition.validate() }
        }
    }
}
