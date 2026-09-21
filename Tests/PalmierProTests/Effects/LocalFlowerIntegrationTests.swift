import AVFoundation
import Foundation
import Testing
@testable import PalmierPro

@MainActor
struct LocalFlowerIntegrationTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PALMIER_TEST_FLOWER_PACKAGE"] != nil))
    func flowerExportsThroughPalmier() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["PALMIER_TEST_FLOWER_PACKAGE"])
        let directory = URL(fileURLWithPath: path)
        let definition = try await Task.detached { try EffectPackage.textStyle(in: directory) }.value
        let baseURL = try await ImageVideoGenerator.blackVideo(size: CGSize(width: 960, height: 540))
        var manifest = MediaManifest()
        manifest.entries = [MediaManifestEntry(id: "base", name: "Base", type: .video,
            source: .external(absolutePath: baseURL.path), duration: 5)]
        let resolver = MediaResolver(manifest: { manifest }, projectURL: { nil })
        var style = TextStyle()
        definition.apply(to: &style)
        var text = Clip(mediaRef: "", mediaType: .text, startFrame: 30, durationFrames: 90)
        text.textContent = "花字测试 ABC 123"
        text.textStyle = style
        let base = Clip(mediaRef: "base", startFrame: 0, durationFrames: 150)
        var timeline = Fixtures.timeline(fps: 30, tracks: [Fixtures.videoTrack(clips: [text]), Fixtures.videoTrack(clips: [base])])
        timeline.width = 960
        timeline.height = 540
        let output = directory.deletingLastPathComponent().appendingPathComponent("palmier-flower.mp4")
        let service = ExportService()
        await service.export(timeline: timeline, resolver: resolver, format: .h264, resolution: .matchTimeline, outputURL: output)
        try #require(service.error == nil)
        let asset = AVURLAsset(url: output)
        #expect(abs(try await asset.load(.duration).seconds - 5) < 0.05)
        let brightness = try await TextExportGlyphTests.frameBrightness(url: output, frameCount: 150)
        #expect(brightness.count == 150)
        #expect(brightness[15] < 0.001)
        #expect(brightness[60] > 0.001)
        #expect(brightness[135] < 0.001)
    }
}
