import Foundation
import Testing
@testable import PalmierPro

@Suite("add_texts track stacking and text animation duration")
@MainActor
struct TextPlacementAndAnimationDurationTests {
    private func textClip(id: String, animation: TextAnimation? = nil) -> Clip {
        var clip = Fixtures.clip(id: id, mediaRef: "text", mediaType: .text, start: 0, duration: 60)
        clip.textContent = id
        clip.textStyle = TextStyle()
        clip.textAnimation = animation
        return clip
    }

    private func entry(_ content: String, _ start: Int, _ end: Int, _ extra: [String: Any] = [:]) -> [String: Any] {
        ["content": content, "startFrame": start, "endFrame": end].merging(extra) { _, new in new }
    }

    @Test func overlappingEntriesStackOnSeparateNewTracksAsOneUndo() async throws {
        let h = ToolHarness()
        let undoManager = UndoManager()
        h.editor.undo.attach(undoManager)
        let initialTracks = h.editor.timeline.tracks.map(\.id)

        let result = await h.runRaw("add_texts", args: ["entries": [
            entry("Title", 0, 180),
            entry("Subtitle", 0, 180),
            entry("Later", 200, 260),
        ]])

        #expect(!result.isError, "\(ToolHarness.textOf(result))")
        let tracks = h.editor.timeline.tracks
        #expect(tracks.count == initialTracks.count + 2)
        #expect(tracks[0].clips.map(\.textContent) == ["Title", "Later"])
        #expect(tracks[1].clips.map(\.textContent) == ["Subtitle"])

        #expect(!(await h.runRaw("undo")).isError)
        #expect(h.editor.timeline.tracks.map(\.id) == initialTracks)
    }

    @Test func overlappingEntriesOnOneExplicitTrackAreRefusedWithoutMutation() async {
        let h = ToolHarness()
        _ = h.editor.insertTrack(at: 0, type: .video)
        let before = h.editor.timeline

        let result = await h.runRaw("add_texts", args: ["entries": [
            entry("Title", 0, 180, ["trackIndex": 0]),
            entry("Subtitle", 90, 120, ["trackIndex": 0]),
        ]])

        #expect(result.isError)
        #expect(ToolHarness.textOf(result).contains("entries[0] and entries[1] overlap"))
        #expect(h.editor.timeline == before)
    }

    @Test func addTextsSetsEntranceDuration() async {
        let h = ToolHarness()

        let result = await h.runRaw("add_texts", args: ["entries": [
            entry("Title", 0, 180, ["animation": "popIn", "animationDurationFrames": 54]),
        ]])

        #expect(!result.isError, "\(ToolHarness.textOf(result))")
        let clip = h.editor.timeline.tracks.flatMap(\.clips).first { $0.textContent == "Title" }
        #expect(clip?.textAnimation?.preset == .popIn)
        #expect(clip?.textAnimation?.durationFrames == 54)
    }

    @Test(arguments: [
        ("wordReveal", 10, "only to the popIn and slideUp"),
        (nil, 10, "only to the popIn and slideUp"),
        ("popIn", 61, "exceeds the clip's 60 frames"),
        ("popIn", 0, "positive integer"),
        ("popIn", 1.5, "positive integer"),
    ] as [(String?, Double, String)])
    func addTextsRefusesInvalidAnimationDuration(preset: String?, frames: Double, message: String) async {
        var extra: [String: Any] = ["animationDurationFrames": frames]
        extra["animation"] = preset
        let h = ToolHarness()
        let before = h.editor.timeline

        let result = await h.runRaw("add_texts", args: ["entries": [entry("Title", 0, 60, extra)]])

        #expect(result.isError)
        #expect(ToolHarness.textOf(result).contains(message), "\(ToolHarness.textOf(result))")
        #expect(h.editor.timeline == before)
    }

    @Test func updateTextSetsDurationOnTheCurrentEntrancePreset() async {
        let clip = textClip(id: "title", animation: TextAnimation(preset: .slideUp))
        let h = ToolHarness(timeline: Fixtures.timeline(tracks: [Fixtures.videoTrack(clips: [clip])]))

        let result = await h.runRaw("update_text", args: ["clipIds": ["title"], "animationDurationFrames": 30])

        #expect(!result.isError, "\(ToolHarness.textOf(result))")
        #expect(h.editor.clipFor(id: "title")?.textAnimation == TextAnimation(preset: .slideUp, durationFrames: 30))
    }

    @Test func updateTextRefusesDurationForClipsWithoutEntrancePreset() async {
        let entrance = textClip(id: "entrance", animation: TextAnimation(preset: .popIn))
        var plain = textClip(id: "plain")
        plain.startFrame = 60
        let h = ToolHarness(timeline: Fixtures.timeline(tracks: [Fixtures.videoTrack(clips: [entrance, plain])]))
        let before = h.editor.timeline

        let result = await h.runRaw("update_text", args: [
            "clipIds": ["entrance", "plain"],
            "animationDurationFrames": 30,
        ])

        #expect(result.isError)
        #expect(ToolHarness.textOf(result).contains("plain"))
        #expect(h.editor.timeline == before)
    }

    @Test(arguments: [
        ("slideUp", 54),
        ("wordReveal", TextAnimation.defaultDurationFrames),
    ])
    func switchingPresetKeepsDurationOnlyWithinEntrancePresets(preset: String, expected: Int) async {
        let clip = textClip(id: "title", animation: TextAnimation(preset: .popIn, durationFrames: 54))
        let h = ToolHarness(timeline: Fixtures.timeline(tracks: [Fixtures.videoTrack(clips: [clip])]))

        let result = await h.runRaw("update_text", args: ["clipIds": ["title"], "animation": preset])

        #expect(!result.isError, "\(ToolHarness.textOf(result))")
        #expect(h.editor.clipFor(id: "title")?.textAnimation?.durationFrames == expected)
    }
}
