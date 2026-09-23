import Foundation
import Testing
@testable import PalmierPro

@MainActor
struct LinearMaskMutationTests {
    @Test func disablePreservesMaskAndShapeReplacementUndoes() throws {
        let editor = EditorViewModel()
        let manager = UndoManager()
        editor.undo.attach(manager)
        var clip = Fixtures.clip(id: "mask", start: 0, duration: 60)
        let shape = MaskShape(linear: .init(rotation: -90), feather: 0.6)
        clip.mask = shape
        clip.maskTrack = KeyframeTrack(keyframes: [Keyframe(frame: 0, value: shape)])
        editor.timeline = Fixtures.timeline(tracks: [Fixtures.videoTrack(clips: [clip])])
        editor.setMaskEnabled(clipId: clip.id, enabled: false)
        let disabled = try #require(editor.clipFor(id: clip.id))
        #expect(!disabled.maskEnabled)
        #expect(disabled.mask == shape)
        #expect(disabled.maskTrack == clip.maskTrack)
        #expect(try JSONDecoder().decode(Clip.self, from: JSONEncoder().encode(disabled)) == disabled)
        editor.beginMaskEditing(clipId: clip.id, linear: false)
        #expect(editor.clipFor(id: clip.id)?.mask == nil)
        #expect(editor.clipFor(id: clip.id)?.maskTrack == nil)
        #expect(editor.undo.undoLatest() == "Change Mask Shape")
        #expect(editor.clipFor(id: clip.id) == disabled)
        #expect(editor.undo.undoLatest() == "Toggle Mask")
        #expect(editor.clipFor(id: clip.id) == clip)
    }

    @Test func featherGestureIsOneUndoStep() throws {
        let editor = EditorViewModel()
        let manager = UndoManager()
        editor.undo.attach(manager)
        var clip = Fixtures.clip(id: "mask", start: 0, duration: 60)
        clip.mask = MaskShape(linear: .init(), feather: 0)
        editor.timeline = Fixtures.timeline(tracks: [Fixtures.videoTrack(clips: [clip])])
        editor.setMaskFeather(clipId: clip.id, feather: 0.2, commit: false)
        editor.setMaskFeather(clipId: clip.id, feather: 0.4, commit: false)
        editor.setMaskFeather(clipId: clip.id, feather: 0.6, commit: true)
        #expect(editor.clipFor(id: clip.id)?.mask?.feather == 0.6)
        #expect(editor.undo.undoLatest() == "Change Mask Feather")
        #expect(editor.clipFor(id: clip.id)?.mask?.feather == 0)
        #expect(!manager.canUndo)
    }

    @Test func animatedPathStyleEditsReachSampledShape() throws {
        let editor = EditorViewModel()
        var clip = Fixtures.clip(id: "path", start: 0, duration: 60)
        let shape = MaskShape(vertices: [MaskVertex(x: 0, y: 0), MaskVertex(x: 1, y: 0), MaskVertex(x: 1, y: 1)])
        clip.mask = shape
        clip.maskTrack = KeyframeTrack(keyframes: [Keyframe(frame: 0, value: shape)])
        editor.timeline = Fixtures.timeline(tracks: [Fixtures.videoTrack(clips: [clip])])
        editor.currentFrame = 15
        editor.setMaskFeather(clipId: clip.id, feather: 0.6, commit: true)
        editor.setMaskInverted(clipId: clip.id, inverted: true)
        let edited = try #require(editor.clipFor(id: clip.id)?.maskAt(frame: 15))
        #expect(edited.feather == 0.6)
        #expect(edited.inverted)
        #expect(editor.clipFor(id: clip.id)?.maskTrack?.keyframes.first?.value == shape)
    }

    @Test func parameterEditUndoesAndPreservesAnimation() throws {
        let editor = EditorViewModel()
        let manager = UndoManager()
        editor.undo.attach(manager)
        var clip = Fixtures.clip(id: "mask", start: 0, duration: 60)
        let shape = MaskShape(linear: .init(), feather: 0)
        clip.mask = shape
        clip.maskTrack = KeyframeTrack(keyframes: [Keyframe(frame: 0, value: shape)])
        editor.timeline = Fixtures.timeline(tracks: [Fixtures.videoTrack(clips: [clip])])
        editor.currentFrame = 15
        editor.setLinearMaskValue(clipId: clip.id, keyPath: \.rotation, value: -90)
        #expect(editor.clipFor(id: clip.id)?.maskAt(frame: 15)?.linear?.rotation == -90)
        #expect(editor.clipFor(id: clip.id)?.maskTrack?.keyframes.first?.value == shape)
        #expect(editor.undo.undoLatest() == "Change Linear Mask")
        #expect(editor.clipFor(id: clip.id)?.maskTrack?.keyframes.count == 1)
        editor.setMaskFeather(clipId: clip.id, feather: 0.6, commit: true)
        editor.setMaskInverted(clipId: clip.id, inverted: true)
        let edited = try #require(editor.clipFor(id: clip.id)?.maskAt(frame: 15))
        #expect(edited.feather == 0.6)
        #expect(edited.inverted)
        #expect(editor.clipFor(id: clip.id)?.maskTrack?.keyframes.first?.value == shape)
    }
}
