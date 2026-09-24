import CoreGraphics
import Testing
@testable import PalmierPro

@Suite("Timeline clip animation ranges")
@MainActor
struct ClipAnimationRangeRenderTests {
    private let size = (width: 300, height: 60)

    private func render(_ clip: Clip) throws -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: size.width * size.height * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(
                data: buffer.baseAddress, width: size.width, height: size.height, bitsPerComponent: 8,
                bytesPerRow: size.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            ClipRenderer.draw(
                clip, type: .image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height),
                isSelected: false, context: context, fps: 30
            )
        }
        return pixels
    }

    /// Columns where the two renders differ anywhere.
    private func changedColumns(_ a: [UInt8], _ b: [UInt8]) -> Set<Int> {
        var columns = Set<Int>()
        for index in stride(from: 0, to: a.count, by: 4) where a[index..<index + 4] != b[index..<index + 4] {
            columns.insert((index / 4) % size.width)
        }
        return columns
    }

    @Test func barsSpanExactlyTheAnimatedFrames() throws {
        let plain = Fixtures.clip(id: "c", mediaRef: "m", mediaType: .image, start: 0, duration: 100)
        var animated = plain
        animated.inAnimation = ClipAnimation(preset: .slideLeft, durationFrames: 20)
        animated.outAnimation = ClipAnimation(preset: .zoomOut, durationFrames: 10)

        let columns = changedColumns(try render(plain), try render(animated))

        #expect(columns.contains(30))
        #expect(columns.contains(285))
        #expect(!columns.contains(65))
        #expect(!columns.contains(150))
        #expect(!columns.contains(265))
    }
}
