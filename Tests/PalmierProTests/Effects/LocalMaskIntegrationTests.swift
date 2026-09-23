import AVFoundation
import Foundation
import Testing
@testable import PalmierPro

@MainActor
struct LocalMaskIntegrationTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PALMIER_TEST_MASK_SOURCE"] != nil))
    func linearMaskExportsThroughPalmier() async throws {
        let directory = try #require(ProcessInfo.processInfo.environment["PALMIER_TEST_MASK_SOURCE"])
        let outputPath = try #require(ProcessInfo.processInfo.environment["PALMIER_TEST_MASK_OUTPUT"])
        var manifest = MediaManifest()
        manifest.entries = ["s3-a", "s3-b"].map { name in
            MediaManifestEntry(id: name, name: name, type: .video,
                source: .external(absolutePath: directory + "/" + name + ".mp4"), duration: 8)
        }
        let resolver = MediaResolver(manifest: { manifest }, projectURL: { nil })
        var upper = Clip(mediaRef: "s3-b", startFrame: 0, durationFrames: 240)
        upper.mask = MaskShape(linear: .init(rotation: -90), feather: 0.6)
        let lower = Clip(mediaRef: "s3-a", startFrame: 0, durationFrames: 240)
        var timeline = Fixtures.timeline(fps: 30, tracks: [Fixtures.videoTrack(clips: [upper]), Fixtures.videoTrack(clips: [lower])])
        timeline.width = 1080
        timeline.height = 608
        if let projectPath = ProcessInfo.processInfo.environment["PALMIER_TEST_MASK_PROJECT"] {
            let projectTimeline = timeline
            let projectManifest = manifest
            let loaded = try await Task.detached {
                let url = URL(fileURLWithPath: projectPath)
                let fm = FileManager.default
                guard !fm.fileExists(atPath: url.path) else { throw CocoaError(.fileWriteFileExists) }
                var bundled = projectManifest
                for index in bundled.entries.indices {
                    let name = bundled.entries[index].id + ".mp4"
                    bundled.entries[index].source = .project(relativePath: "media/" + name)
                    bundled.entries[index].sourceWidth = 1080
                    bundled.entries[index].sourceHeight = 608
                    bundled.entries[index].sourceFPS = 30
                    bundled.entries[index].hasAudio = false
                }
                let file = ProjectFile(timelines: [projectTimeline], activeTimelineId: projectTimeline.id,
                                       openTimelineIds: [projectTimeline.id])
                try VideoProject.writeProjectPackage(.init(timeline: JSONEncoder().encode(file),
                    manifest: JSONEncoder().encode(bundled), thumbnail: nil, chatSessionFiles: []),
                    to: url, sourceURL: nil)
                for entry in bundled.entries {
                    try fm.copyItem(at: URL(fileURLWithPath: directory + "/" + entry.id + ".mp4"),
                                    to: url.appendingPathComponent("media/" + entry.id + ".mp4"))
                }
                return try VideoProject.readProjectPackage(at: url)
            }.value
            #expect(loaded.projectFile.timelines.first == timeline)
            #expect(loaded.manifest?.entries.count == 2)
        }
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
