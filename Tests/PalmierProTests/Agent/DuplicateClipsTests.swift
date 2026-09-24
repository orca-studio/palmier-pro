import Foundation
import Testing
@testable import PalmierPro

@Suite("duplicate_clips")
@MainActor
struct DuplicateClipsTests {
    private func richClip(id: String = "v", start: Int = 10) -> Clip {
        var clip = Fixtures.clip(id: id, start: start, duration: 60, speed: 2)
        clip.opacityTrack = KeyframeTrack(keyframes: [Keyframe(frame: 0, value: 0), Keyframe(frame: 20, value: 1)])
        clip.mask = MaskShape(linear: LinearMaskGeometry(rotation: 90))
        clip.outAnimation = ClipAnimation(preset: .slideLeft, durationFrames: 30)
        clip.fadeInFrames = 5
        return clip
    }

    private func harness(_ tracks: [Track]) -> (ToolHarness, UndoManager) {
        let h = ToolHarness(timeline: Fixtures.timeline(tracks: tracks))
        let undoManager = UndoManager()
        h.editor.undo.attach(undoManager)
        return (h, undoManager)
    }

    /// Receipts use short ids; resolve them to the full clip id.
    private func copyId(_ result: Any, of source: String, in h: ToolHarness) -> String? {
        guard let short = ((result as? [String: Any])?["copies"] as? [[String: String]])?
            .first(where: { $0["sourceClipId"].map { source.hasPrefix($0) } ?? false })?["clipId"] else { return nil }
        return h.editor.timeline.tracks.flatMap(\.clips).first { $0.id.hasPrefix(short) }?.id
    }

    @Test func copiesTheWholeClipOntoANewTrackAboveAsOneUndo() async throws {
        let (h, undoManager) = harness([Fixtures.videoTrack(id: "V1", clips: [richClip()])])
        defer { withExtendedLifetime(undoManager) {} }

        let result = try await h.runOK("duplicate_clips", args: ["clipIds": ["v"]])

        let id = try #require(copyId(result, of: "v", in: h))
        let tracks = h.editor.timeline.tracks
        #expect(tracks.count == 2)
        #expect(tracks[1].id == "V1")
        var copy = try #require(tracks[0].clips.first)
        #expect(copy.id == id)
        copy.id = "v"
        #expect(copy == richClip())

        #expect(!(await h.runRaw("undo")).isError)
        #expect(h.editor.timeline.tracks.map(\.id) == ["V1"])
        #expect(h.editor.timeline.tracks[0].clips.map(\.id) == ["v"])
    }

    @Test func linkedAudioIsDuplicatedBelowAndStaysLinked() async throws {
        var video = Fixtures.clip(id: "v", start: 0, duration: 60)
        var audio = Fixtures.clip(id: "a", mediaType: .audio, start: 0, duration: 60)
        video.linkGroupId = "g"
        audio.linkGroupId = "g"
        let (h, _) = harness([Fixtures.videoTrack(id: "V1", clips: [video]), Fixtures.audioTrack(id: "A1", clips: [audio])])

        let result = try await h.runOK("duplicate_clips", args: ["clipIds": ["v"]])

        let videoId = try #require(copyId(result, of: "v", in: h))
        let audioId = try #require(copyId(result, of: "a", in: h))
        let videoCopy = try #require(h.editor.clipFor(id: videoId))
        let audioCopy = try #require(h.editor.clipFor(id: audioId))
        #expect(videoCopy.linkGroupId != nil && videoCopy.linkGroupId == audioCopy.linkGroupId)
        #expect(videoCopy.linkGroupId != "g")
        #expect(h.editor.timeline.tracks.map(\.type) == [.video, .video, .audio, .audio])
        #expect(h.editor.timeline.tracks[3].clips.first?.id == audioCopy.id)
    }

    @Test func sameTracksPlacesTheCopyLaterOnTheSourceTrack() async throws {
        let (h, _) = harness([Fixtures.videoTrack(id: "V1", clips: [Fixtures.clip(id: "v", start: 0, duration: 30)])])

        let result = try await h.runOK("duplicate_clips", args: ["clipIds": ["v"], "placement": "sameTracks", "startFrame": 30])

        let copyClipId = try #require(copyId(result, of: "v", in: h))
        let copy = try #require(h.editor.clipFor(id: copyClipId))
        #expect(h.editor.timeline.tracks.count == 1)
        #expect(copy.startFrame == 30)
    }

    @Test func startFrameShiftsCopiesTogether() async throws {
        let (h, _) = harness([Fixtures.videoTrack(id: "V1", clips: [
            Fixtures.clip(id: "a", start: 10, duration: 20), Fixtures.clip(id: "b", start: 40, duration: 20),
        ])])

        let result = try await h.runOK("duplicate_clips", args: ["clipIds": ["a", "b"], "startFrame": 100])

        let a = try #require(copyId(result, of: "a", in: h))
        let b = try #require(copyId(result, of: "b", in: h))
        #expect(h.editor.clipFor(id: a)?.startFrame == 100)
        #expect(h.editor.clipFor(id: b)?.startFrame == 130)
    }

    @Test(arguments: [
        (["clipIds": ["missing"]] as [String: any Sendable], "Clip not found"),
        (["clipIds": [String]()] as [String: any Sendable], "non-empty"),
        (["clipIds": ["v"], "placement": "overlay"] as [String: any Sendable], "placement must be"),
        (["clipIds": ["v"], "placement": "sameTracks"] as [String: any Sendable], "needs a startFrame"),
        (["clipIds": ["v"], "placement": "sameTracks", "startFrame": 20] as [String: any Sendable], "would overwrite v"),
        (["clipIds": ["v"], "startFrame": -1] as [String: any Sendable], "startFrame must be >= 0"),
    ])
    func refusesInvalidRequestsWithoutMutation(args: [String: any Sendable], message: String) async {
        let (h, undoManager) = harness([Fixtures.videoTrack(id: "V1", clips: [Fixtures.clip(id: "v", start: 0, duration: 60)])])
        let before = h.editor.timeline

        let result = await h.runRaw("duplicate_clips", args: args)

        #expect(result.isError)
        #expect(ToolHarness.textOf(result).contains(message), "\(ToolHarness.textOf(result))")
        #expect(h.editor.timeline == before)
        #expect(!undoManager.canUndo)
    }
}
