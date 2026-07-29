import CoreImage
import Foundation
import Testing
@testable import PalmierPro

@Suite("Path mask")
struct PathMaskTests {

    private let ctx = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
    private let extent = CGRect(x: 0, y: 0, width: 64, height: 64)

    private func white() -> CIImage {
        CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: extent)
    }

    /// Alpha at one source pixel after masking. `y` is measured downward, matching
    /// the vertex coordinate space.
    private func alpha(_ image: CIImage, x: Int, y: Int) -> Double {
        var px = [Float](repeating: 0, count: 4)
        ctx.render(
            image, toBitmap: &px, rowBytes: 16,
            bounds: CGRect(x: CGFloat(x), y: extent.height - 1 - CGFloat(y), width: 1, height: 1),
            format: .RGBAf, colorSpace: nil
        )
        return Double(px[3])
    }

    /// Left half of the frame.
    private var leftHalf: MaskShape {
        MaskShape(vertices: [
            MaskVertex(x: 0, y: 0), MaskVertex(x: 0.5, y: 0),
            MaskVertex(x: 0.5, y: 1), MaskVertex(x: 0, y: 1),
        ])
    }

    @Test func keepsInsideAndCutsOutside() {
        let out = PathMaskRasterizer.apply(white(), shape: leftHalf, extent: extent)
        #expect(alpha(out, x: 16, y: 32) > 0.95, "inside the path stays opaque")
        #expect(alpha(out, x: 48, y: 32) < 0.05, "outside the path is cut away")
    }

    @Test func invertedSwapsWhichSideSurvives() {
        var shape = leftHalf
        shape.inverted = true
        let out = PathMaskRasterizer.apply(white(), shape: shape, extent: extent)
        #expect(alpha(out, x: 16, y: 32) < 0.05)
        #expect(alpha(out, x: 48, y: 32) > 0.95)
    }

    @Test func yRunsDownwardFromTheTopEdge() {
        // Top half: y from 0 to 0.5 must cover the TOP of the image, not the bottom.
        let topHalf = MaskShape(vertices: [
            MaskVertex(x: 0, y: 0), MaskVertex(x: 1, y: 0),
            MaskVertex(x: 1, y: 0.5), MaskVertex(x: 0, y: 0.5),
        ])
        let out = PathMaskRasterizer.apply(white(), shape: topHalf, extent: extent)
        #expect(alpha(out, x: 32, y: 8) > 0.95, "near the top edge survives")
        #expect(alpha(out, x: 32, y: 56) < 0.05, "near the bottom edge is cut")
    }

    @Test func fewerThanThreeVerticesIsANoOp() {
        let degenerate = MaskShape(vertices: [MaskVertex(x: 0, y: 0), MaskVertex(x: 1, y: 1)])
        #expect(!degenerate.isRenderable)
        let out = PathMaskRasterizer.apply(white(), shape: degenerate, extent: extent)
        #expect(alpha(out, x: 48, y: 32) > 0.95, "an unclosable path must not cut anything")
    }

    @Test func featherProducesPartialAlphaAtTheEdge() {
        var shape = leftHalf
        shape.feather = 0.25
        let out = PathMaskRasterizer.apply(white(), shape: shape, extent: extent)
        let onEdge = alpha(out, x: 32, y: 32)
        #expect(onEdge > 0.05 && onEdge < 0.95, "the boundary should be partially transparent, got \(onEdge)")
    }
}

@Suite("MaskShape interpolation")
struct MaskShapeInterpolationTests {

    private func triangle(_ dx: Double) -> MaskShape {
        MaskShape(vertices: [
            MaskVertex(x: 0.0 + dx, y: 0.0), MaskVertex(x: 0.5 + dx, y: 0.0), MaskVertex(x: 0.25 + dx, y: 0.5),
        ])
    }

    @Test func matchingCountsMorphVertexByVertex() {
        let mid = MaskShape.keyframeInterpolate(triangle(0), triangle(0.4), t: 0.5)
        #expect(mid.vertices.count == 3)
        #expect(abs(mid.vertices[0].x - 0.2) < 1e-9)
        #expect(abs(mid.vertices[2].x - 0.45) < 1e-9)
        #expect(abs(mid.vertices[2].y - 0.5) < 1e-9, "y is unchanged between the two shapes")
    }

    /// The invariant the whole feature rests on: pairing anchors by index is only
    /// meaningful when both paths have the same number of them.
    @Test func mismatchedCountsHoldInsteadOfGuessing() {
        var square = triangle(0)
        square.vertices.append(MaskVertex(x: 0.1, y: 0.9))
        let mid = MaskShape.keyframeInterpolate(triangle(0), square, t: 0.5)
        #expect(mid == triangle(0), "a count mismatch must hold the earlier shape verbatim")
    }

    @Test func trackSamplingAnimatesTheClipsMask() {
        var clip = Clip(mediaRef: "m", startFrame: 100, durationFrames: 20)
        clip.maskTrack = KeyframeTrack(keyframes: [
            Keyframe(frame: 0, value: triangle(0), interpolationOut: .linear),
            Keyframe(frame: 10, value: triangle(0.4), interpolationOut: .linear),
        ])
        // Frames are clip-relative in storage, absolute at the call site.
        let sampled = clip.maskAt(frame: 105)
        #expect(sampled != nil)
        #expect(abs((sampled?.vertices[0].x ?? 0) - 0.2) < 1e-9)
    }

    @Test func splittingAClipRebasesThePath() {
        let track = KeyframeTrack(keyframes: [
            Keyframe(frame: 0, value: triangle(0), interpolationOut: .linear),
            Keyframe(frame: 10, value: triangle(0.4), interpolationOut: .linear),
        ])
        let rebased = track.rebased(by: 5, fallback: triangle(0))
        #expect(rebased?.keyframes.first?.frame == 0)
        #expect(abs((rebased?.keyframes.first?.value.vertices[0].x ?? 0) - 0.2) < 1e-9,
                "the boundary keyframe carries the interpolated shape")
    }

    @Test func decodeDropsNonFiniteVertices() {
        var shape = MaskShape(vertices: [
            MaskVertex(x: 0, y: 0), MaskVertex(x: .nan, y: 0.5), MaskVertex(x: 1, y: 1),
        ])
        shape.feather = .infinity
        let clean = shape.sanitized
        #expect(clean.vertices.count == 2)
        #expect(clean.feather == 0)
        #expect(!clean.isRenderable, "a sanitized path that lost too many anchors stops rendering")
    }
}

@Suite("Mask vertex editing")
@MainActor
struct MaskVertexEditingTests {

    private func editorWithMaskedClip(animated: Bool) -> (EditorViewModel, String) {
        let editor = EditorViewModel()
        var clip = Clip(mediaRef: "m", startFrame: 0, durationFrames: 30)
        let square = MaskShape(vertices: [
            MaskVertex(x: 0.2, y: 0.2), MaskVertex(x: 0.8, y: 0.2),
            MaskVertex(x: 0.8, y: 0.8), MaskVertex(x: 0.2, y: 0.8),
        ])
        clip.mask = square
        if animated {
            var shifted = square
            shifted.vertices = square.vertices.map { MaskVertex(x: $0.x + 0.05, y: $0.y) }
            clip.maskTrack = KeyframeTrack(keyframes: [
                Keyframe(frame: 0, value: square, interpolationOut: .linear),
                Keyframe(frame: 20, value: shifted, interpolationOut: .linear),
            ])
        }
        editor.timeline.tracks = [Track(type: .video, clips: [clip])]
        return (editor, clip.id)
    }

    /// The invariant, enforced at the editing layer: a new point lands on every
    /// keyframe, so interpolation keeps its one-to-one anchor pairing.
    @Test func insertingAVertexTouchesEveryKeyframe() {
        let (editor, id) = editorWithMaskedClip(animated: true)
        editor.insertMaskVertex(clipId: id, afterIndex: 0)
        let clip = editor.clipFor(id: id)
        #expect(clip?.mask?.vertices.count == 5)
        #expect(clip?.maskTrack?.keyframes.allSatisfy { $0.value.vertices.count == 5 } == true)
    }

    @Test func deletingAVertexTouchesEveryKeyframe() {
        let (editor, id) = editorWithMaskedClip(animated: true)
        editor.removeMaskVertex(clipId: id, index: 1)
        let clip = editor.clipFor(id: id)
        #expect(clip?.mask?.vertices.count == 3)
        #expect(clip?.maskTrack?.keyframes.allSatisfy { $0.value.vertices.count == 3 } == true)
    }

    @Test func deletingBelowThreeVerticesIsRefused() {
        let (editor, id) = editorWithMaskedClip(animated: false)
        editor.removeMaskVertex(clipId: id, index: 0)   // 4 -> 3
        editor.removeMaskVertex(clipId: id, index: 0)   // refused
        #expect(editor.clipFor(id: id)?.mask?.vertices.count == 3)
    }

    /// Dragging a point during an animation must extend the animation, not flatten it.
    @Test func draggingWithALiveTrackKeyframesAtThePlayhead() {
        let (editor, id) = editorWithMaskedClip(animated: true)
        editor.seekToFrame(10)
        var moved = editor.clipFor(id: id)!.maskAt(frame: 10)!
        moved.vertices[0].point = AnimPair(a: 0.4, b: 0.4)
        editor.commitMaskShape(clipId: id, shape: moved)
        let track = editor.clipFor(id: id)?.maskTrack
        #expect(track?.keyframes.count == 3, "a third keyframe should appear at the playhead")
        #expect(track?.keyframes.contains { $0.frame == 10 } == true)
    }

    @Test func draggingWithoutATrackEditsTheStaticShape() {
        let (editor, id) = editorWithMaskedClip(animated: false)
        var moved = editor.clipFor(id: id)!.mask!
        moved.vertices[0].point = AnimPair(a: 0.4, b: 0.4)
        editor.commitMaskShape(clipId: id, shape: moved)
        #expect(editor.clipFor(id: id)?.maskTrack == nil, "no track should be created by a plain drag")
        #expect(editor.clipFor(id: id)?.mask?.vertices[0].x == 0.4)
    }

    @Test func clearingRemovesBothShapeAndTrack() {
        let (editor, id) = editorWithMaskedClip(animated: true)
        editor.clearMask(clipId: id)
        #expect(editor.clipFor(id: id)?.mask == nil)
        #expect(editor.clipFor(id: id)?.maskTrack == nil)
        #expect(editor.clipFor(id: id)?.hasMask == false)
    }
}
