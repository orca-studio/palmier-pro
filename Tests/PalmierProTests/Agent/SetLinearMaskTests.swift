import Foundation
import Testing
@testable import PalmierPro

@Suite("set_mask linear masks")
@MainActor
struct SetLinearMaskTests {
    private func harness(_ clip: Clip = Fixtures.clip(id: "v", start: 0, duration: 60)) -> ToolHarness {
        ToolHarness(timeline: Fixtures.timeline(tracks: [Fixtures.videoTrack(clips: [clip])]))
    }

    @Test func createsALinearMaskFromSourceBoxCoordinates() async throws {
        let h = harness()

        _ = try await h.runOK("set_mask", args: [
            "clipIds": ["v"],
            "linear": ["center": [0.75, 0.5], "rotation": 90],
            "inverted": true,
        ])

        let mask = try #require(h.editor.clipFor(id: "v")?.mask)
        #expect(mask.linear == LinearMaskGeometry(centerX: 0.5, centerY: 0, rotation: 90))
        #expect(mask.vertices.isEmpty)
        #expect(mask.inverted)
    }

    @Test func partialLinearEditKeepsTheOtherField() async throws {
        var clip = Fixtures.clip(id: "v", start: 0, duration: 60)
        clip.mask = MaskShape(linear: LinearMaskGeometry(centerX: 0.2, centerY: 0, rotation: 0))
        let h = harness(clip)

        _ = try await h.runOK("set_mask", args: ["clipIds": ["v"], "linear": ["rotation": 90]])

        #expect(h.editor.clipFor(id: "v")?.mask?.linear == LinearMaskGeometry(centerX: 0.2, centerY: 0, rotation: 90))
    }

    @Test func verticesReplaceALinearMask() async throws {
        var clip = Fixtures.clip(id: "v", start: 0, duration: 60)
        clip.mask = MaskShape(linear: LinearMaskGeometry(rotation: 90))
        let h = harness(clip)

        _ = try await h.runOK("set_mask", args: ["clipIds": ["v"], "vertices": [[0, 0], [1, 0], [1, 1]]])

        let mask = try #require(h.editor.clipFor(id: "v")?.mask)
        #expect(mask.linear == nil)
        #expect(mask.vertices.count == 3)
    }

    @Test(arguments: [
        (["vertices": [[0, 0], [1, 0], [1, 1]], "linear": ["rotation": 90]] as [String: any Sendable], "not both"),
        (["linear": ["rotation": 90], "remove": true] as [String: any Sendable], "not both"),
        (["linear": [:] as [String: any Sendable]] as [String: any Sendable], "pass center, rotation, or both"),
        (["linear": ["rotation": 720]] as [String: any Sendable], "between -360 and 360"),
        (["linear": ["center": [0.5]]] as [String: any Sendable], "expected [x, y]"),
        (["linear": ["angle": 90]] as [String: any Sendable], "angle"),
    ])
    func refusesInvalidLinearRequestsWithoutMutation(fields: [String: any Sendable], message: String) async {
        let h = harness()
        let before = h.editor.timeline
        var args: [String: Any] = ["clipIds": ["v"]]
        for (key, value) in fields { args[key] = value }

        let result = await h.runRaw("set_mask", args: args)

        #expect(result.isError)
        #expect(ToolHarness.textOf(result).contains(message), "\(ToolHarness.textOf(result))")
        #expect(h.editor.timeline == before)
    }

    @Test func refusesTurningAnAnimatedPathIntoALinearMask() async {
        var clip = Fixtures.clip(id: "v", start: 0, duration: 60)
        let path = MaskShape(vertices: [MaskVertex(x: 0, y: 0), MaskVertex(x: 1, y: 0), MaskVertex(x: 1, y: 1)])
        clip.mask = path
        clip.maskTrack = KeyframeTrack(keyframes: [Keyframe(frame: 0, value: path), Keyframe(frame: 30, value: path)])
        let h = harness(clip)

        let result = await h.runRaw("set_mask", args: ["clipIds": ["v"], "linear": ["rotation": 90]])

        #expect(result.isError)
        #expect(ToolHarness.textOf(result).contains("remove:true"))
        #expect(h.editor.clipFor(id: "v")?.mask?.linear == nil)
    }
}
