import Foundation
import Testing
@testable import PalmierPro

struct SequenceEffectTests {
    let sequence = SequenceEffect(sourceFrames: 151, sourceFPS: 25, width: 500, height: 281, blendMode: .screen)

    @Test func mapsNativeControlsAndPersists() throws {
        let clip = try sequence.clip(mediaRef: "stars", startFrame: 30, durationFrames: 90, fps: 30, speedControl: 0.33, intensity: 0.7)
        #expect(abs(clip.speed - 0.995) < 0.000001)
        #expect(clip.opacity == 0.7)
        #expect(clip.blendMode == .screen)
        #expect(try JSONDecoder().decode(Clip.self, from: JSONEncoder().encode(clip)) == clip)
    }

    @Test func rejectsInvalidControlsAndDuration() {
        for speed in [Double.nan, -.infinity, -0.1, 1.1] {
            #expect(throws: (any Error).self) {
                try sequence.clip(mediaRef: "stars", startFrame: 0, durationFrames: 30, fps: 30, speedControl: speed, intensity: 1)
            }
        }
        #expect(throws: (any Error).self) {
            try sequence.clip(mediaRef: "stars", startFrame: 0, durationFrames: 300, fps: 30, speedControl: 1, intensity: 1)
        }
    }
}
