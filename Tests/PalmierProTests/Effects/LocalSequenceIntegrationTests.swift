import AVFoundation
import Foundation
import Testing
@testable import PalmierPro

@MainActor
struct LocalSequenceIntegrationTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PALMIER_TEST_SEQUENCE"] != nil))
    func capturedStarsExportThroughPalmier() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["PALMIER_TEST_SEQUENCE"])
        let directory = URL(fileURLWithPath: path)
        let (url, sequence) = try await Task.detached { try EffectPackage.sequenceURL(in: directory) }.value
        let baseURL = try await ImageVideoGenerator.blackVideo(size: CGSize(width: 640, height: 360))
        var manifest = MediaManifest()
        manifest.entries = [
            MediaManifestEntry(id: "stars", name: "Star II", type: .video, source: .external(absolutePath: url.path), duration: 151.0 / 25),
            MediaManifestEntry(id: "base", name: "Base", type: .video, source: .external(absolutePath: baseURL.path), duration: 5)
        ]
        let resolver = MediaResolver(manifest: { manifest }, projectURL: { nil })
        let stars = try sequence.clip(mediaRef: "stars", startFrame: 0, durationFrames: 150, fps: 30, speedControl: 0.33, intensity: 1)
        let base = Clip(mediaRef: "base", startFrame: 0, durationFrames: 150)
        var timeline = Fixtures.timeline(fps: 30, tracks: [Fixtures.videoTrack(clips: [stars]), Fixtures.videoTrack(clips: [base])])
        timeline.width = 640
        timeline.height = 360
        let output = directory.deletingLastPathComponent().appendingPathComponent("palmier-stars.mp4")
        let service = ExportService()
        await service.export(timeline: timeline, resolver: resolver, format: .h264, resolution: .matchTimeline, outputURL: output)
        #expect(service.error == nil)
        let asset = AVURLAsset(url: output)
        #expect(abs(try await asset.load(.duration).seconds - 5) < 0.05)
        let generator = AVAssetImageGenerator(asset: asset)
        let first = try await generator.image(at: CMTime(seconds: 1, preferredTimescale: 30)).image
        let later = try await generator.image(at: CMTime(seconds: 3, preferredTimescale: 30)).image
        let firstData = try #require(first.dataProvider?.data)
        let laterData = try #require(later.dataProvider?.data)
        #expect(firstData as Data != laterData as Data)
        let brightness = try await TextExportGlyphTests.frameBrightness(url: output, frameCount: 30)
        #expect(brightness.max() ?? 0 > 0.001)
    }
}
