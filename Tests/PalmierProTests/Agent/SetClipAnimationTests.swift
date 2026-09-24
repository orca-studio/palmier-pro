import Foundation
import Testing
@testable import PalmierPro

@Suite("set_clip_properties entrance and exit animations")
@MainActor
struct SetClipAnimationTests {
    private func harness(_ clips: [Clip] = [Fixtures.clip(id: "v", start: 0, duration: 100)]) -> ToolHarness {
        ToolHarness(timeline: Fixtures.timeline(tracks: [Fixtures.videoTrack(clips: clips)]))
    }

    @Test func setsBothAnimationsAsOneUndoStep() async throws {
        let h = harness()
        let undoManager = UndoManager()
        h.editor.undo.attach(undoManager)

        _ = try await h.runOK("set_clip_properties", args: [
            "clipIds": ["v"],
            "inAnimation": ["preset": "zoomIn", "durationFrames": 15],
            "outAnimation": ["preset": "slideLeft", "durationFrames": 85],
        ])

        let clip = try #require(h.editor.clipFor(id: "v"))
        #expect(clip.inAnimation == ClipAnimation(preset: .zoomIn, durationFrames: 15))
        #expect(clip.outAnimation == ClipAnimation(preset: .slideLeft, durationFrames: 85))

        #expect(!(await h.runRaw("undo")).isError)
        #expect(h.editor.clipFor(id: "v")?.inAnimation == nil)
        #expect(h.editor.clipFor(id: "v")?.outAnimation == nil)
    }

    @Test func presetNoneClearsOnlyThatEdge() async throws {
        var clip = Fixtures.clip(id: "v", start: 0, duration: 100)
        clip.inAnimation = ClipAnimation(preset: .slideUp, durationFrames: 10)
        clip.outAnimation = ClipAnimation(preset: .slideDown, durationFrames: 10)
        let h = harness([clip])

        _ = try await h.runOK("set_clip_properties", args: ["clipIds": ["v"], "inAnimation": ["preset": "none"]])

        #expect(h.editor.clipFor(id: "v")?.inAnimation == nil)
        #expect(h.editor.clipFor(id: "v")?.outAnimation == clip.outAnimation)
    }

    @Test func animationsAreValidatedAgainstTheResultingDuration() async throws {
        let h = harness()

        _ = try await h.runOK("set_clip_properties", args: [
            "clipIds": ["v"],
            "durationFrames": 40,
            "outAnimation": ["preset": "slideRight", "durationFrames": 40],
        ])

        #expect(h.editor.clipFor(id: "v")?.outAnimation?.durationFrames == 40)
    }

    @Test(arguments: [
        (["inAnimation": ["preset": "spin", "durationFrames": 10]], "inAnimation.preset must be one of"),
        (["inAnimation": ["preset": "slideLeft"]], "inAnimation.durationFrames must be a positive integer"),
        (["inAnimation": ["preset": "slideLeft", "durationFrames": 0]], "inAnimation.durationFrames must be a positive integer"),
        (["outAnimation": ["preset": "none", "durationFrames": 5]], "must be omitted when preset is 'none'"),
        (["outAnimation": ["preset": "slideLeft", "durationFrames": 10, "easing": "linear"]], "easing"),
        (
            ["inAnimation": ["preset": "zoomIn", "durationFrames": 60], "outAnimation": ["preset": "zoomOut", "durationFrames": 41]],
            "must fit within its resulting duration of 100 frames"
        ),
    ] as [([String: [String: any Sendable]], String)])
    func refusesInvalidRequestsWithoutMutation(fields: [String: [String: any Sendable]], message: String) async {
        let h = harness()
        let before = h.editor.timeline
        var args: [String: Any] = ["clipIds": ["v"]]
        for (key, value) in fields { args[key] = value }

        let result = await h.runRaw("set_clip_properties", args: args)

        #expect(result.isError)
        #expect(ToolHarness.textOf(result).contains(message), "\(ToolHarness.textOf(result))")
        #expect(h.editor.timeline == before)
    }

    @Test func refusesTextClips() async {
        var text = Fixtures.clip(id: "t", mediaRef: "text", mediaType: .text, start: 0, duration: 60)
        text.textContent = "Title"
        let h = harness([text])

        let result = await h.runRaw("set_clip_properties", args: [
            "clipIds": ["t"],
            "inAnimation": ["preset": "slideLeft", "durationFrames": 10],
        ])

        #expect(result.isError)
        #expect(ToolHarness.textOf(result).contains("update_text"))
        #expect(h.editor.clipFor(id: "t")?.inAnimation == nil)
    }
}
