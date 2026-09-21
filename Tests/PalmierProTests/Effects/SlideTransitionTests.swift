import CoreImage
import Foundation
import Testing
@testable import PalmierPro

struct SlideTransitionTests {
    @Test func endpointsDirectionAndSeparator() throws {
        let extent = CGRect(x: 0, y: 0, width: 1000, height: 10)
        let from = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: extent)
        let to = CIImage(color: CIColor(red: 0, green: 0, blue: 1)).cropped(to: extent)
        let context = CIContext()
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        func pixel(_ progress: Double, _ x: Int) -> [UInt8] {
            let image = SlideTransitionRenderer.render(from: from, to: to, progress: progress, extent: extent)
            var bytes = [UInt8](repeating: 0, count: 4)
            context.render(image, toBitmap: &bytes, rowBytes: 4,
                           bounds: CGRect(x: x, y: 5, width: 1, height: 1), format: .RGBA8, colorSpace: space)
            return bytes
        }
        #expect(pixel(0, 500) == [255, 0, 0, 255])
        #expect(pixel(1, 500) == [0, 0, 255, 255])
        #expect(pixel(0.1, 100) == [255, 0, 0, 255])
        #expect(pixel(0.1, 580) == [0, 0, 0, 255])
        #expect(pixel(0.1, 800) == [0, 0, 255, 255])
        #expect(pixel(0.5, 500) == [0, 0, 255, 255])
    }

    @Test func placementRoundtrip() throws {
        var clip = Clip(mediaRef: "source", startFrame: 102, durationFrames: 138)
        clip.entranceTransition = .init(style: .slideBlackBand, durationFrames: 30)
        let restored = try JSONDecoder().decode(Clip.self, from: JSONEncoder().encode(clip))
        #expect(restored == clip)
        #expect(restored.entranceTransition?.progress(atOffset: 0) == 0)
        #expect(restored.entranceTransition?.progress(atOffset: 15) == 0.5)
        #expect(restored.entranceTransition?.progress(atOffset: 30) == nil)
    }
}
