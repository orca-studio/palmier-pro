import AVFoundation
import Foundation
import Testing
@testable import PalmierPro

@MainActor
struct LocalSlideIntegrationTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PALMIER_TEST_SLIDE_SOURCE"] != nil))
    func slideExportsThroughPalmier() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["PALMIER_TEST_SLIDE_SOURCE"])
        let outputPath = try #require(ProcessInfo.processInfo.environment["PALMIER_TEST_SLIDE_OUTPUT"])
        var manifest = MediaManifest()
        manifest.entries = [MediaManifestEntry(id: "source", name: "Motion", type: .video,
            source: .external(absolutePath: path), duration: 8)]
        let resolver = MediaResolver(manifest: { manifest }, projectURL: { nil })
        var incoming = Clip(mediaRef: "source", startFrame: 102, durationFrames: 138)
        incoming.trimStartFrame = 102
        incoming.entranceTransition = .init(style: .slideBlackBand, durationFrames: 30)
        let outgoing = Clip(mediaRef: "source", startFrame: 0, durationFrames: 132)
        var timeline = Fixtures.timeline(fps: 30, tracks: [Fixtures.videoTrack(clips: [incoming]), Fixtures.videoTrack(clips: [outgoing])])
        timeline.width = 960
        timeline.height = 540
        let output = URL(fileURLWithPath: outputPath)
        let service = ExportService()
        await service.export(timeline: timeline, resolver: resolver, format: .h264, resolution: .matchTimeline, outputURL: output)
        try #require(service.error == nil)
        let asset = AVURLAsset(url: output)
        #expect(abs(try await asset.load(.duration).seconds - 8) < 0.05)
        let frames = try await TextExportGlyphTests.frameBrightness(url: output, frameCount: 240)
        #expect(frames.count == 240)
        #expect(frames.allSatisfy { $0 > 0.05 })
    }
}
