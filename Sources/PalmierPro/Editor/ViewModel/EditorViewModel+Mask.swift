import Foundation

// Path-mask editing. Vertex moves follow the same rule as crop and transform:
// while a track is live the playhead gets a keyframe, otherwise the static value
// changes — so dragging a point during an animation extends the animation instead
// of silently flattening it.
extension EditorViewModel {

    /// The clip the pen tool acts on: exactly one selected visual clip.
    var maskEditableClip: Clip? {
        guard activePreviewTab == .timeline else { return nil }
        var match: Clip?
        for track in timeline.tracks where track.type != .audio {
            for clip in track.clips where selectedClipIds.contains(clip.id) {
                if match != nil { return nil }
                match = clip
            }
        }
        return match
    }

    private func writeMask(into clip: inout Clip, shape: MaskShape) {
        if clip.maskTrack?.isActive == true {
            clip.upsertKeyframe(in: \.maskTrack, frame: activeFrame, value: shape)
        } else {
            clip.mask = shape
        }
    }

    /// Live update during a drag; pair with `commitMaskShape` on mouse-up so the whole
    /// gesture lands as one undo step.
    func applyMaskShape(clipId: String, shape: MaskShape) {
        applyClipProperty(clipId: clipId) { self.writeMask(into: &$0, shape: shape) }
    }

    func commitMaskShape(clipId: String, shape: MaskShape, actionName: String = "Move Mask Point") {
        commitClipProperty(clipId: clipId, actionName: actionName) {
            self.writeMask(into: &$0, shape: shape)
        }
    }

    func setMaskShape(clipId: String, shape: MaskShape?, actionName: String) {
        commitClipProperty(clipId: clipId, actionName: actionName) { clip in
            guard let shape else {
                clip.mask = nil
                clip.maskTrack = nil
                return
            }
            self.writeMask(into: &clip, shape: shape)
        }
    }

    func clearMask(clipId: String) {
        setMaskShape(clipId: clipId, shape: nil, actionName: "Clear Mask")
    }

    /// Insert a point on the edge that starts at `index`.
    ///
    /// Vertex count belongs to the track, not to one keyframe: every keyframe gets the
    /// new point at the midpoint of the SAME edge, so the anchor-by-index pairing that
    /// interpolation depends on stays intact. Editing one keyframe alone would leave
    /// the track unable to morph at all.
    func insertMaskVertex(clipId: String, afterIndex index: Int) {
        commitClipProperty(clipId: clipId, actionName: "Add Mask Point") { clip in
            func inserted(_ shape: MaskShape) -> MaskShape {
                var out = shape
                guard out.vertices.count >= 3, index < out.vertices.count else { return out }
                let a = out.vertices[index]
                let b = out.vertices[(index + 1) % out.vertices.count]
                out.vertices.insert(MaskVertex(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2), at: index + 1)
                return out
            }
            if var shape = clip.mask { clip.mask = inserted(shape); shape = clip.mask! }
            if clip.maskTrack?.isActive == true {
                for i in clip.maskTrack!.keyframes.indices {
                    clip.maskTrack!.keyframes[i].value = inserted(clip.maskTrack!.keyframes[i].value)
                }
            }
        }
    }

    /// Remove a point from every keyframe. Refused below four points: three is the
    /// smallest path that still encloses an area.
    func removeMaskVertex(clipId: String, index: Int) {
        guard let clip = clipFor(id: clipId) else { return }
        let count = clip.maskTrack?.keyframes.first?.value.vertices.count ?? clip.mask?.vertices.count ?? 0
        guard count > 3, index < count else { return }
        commitClipProperty(clipId: clipId, actionName: "Delete Mask Point") { clip in
            func removed(_ shape: MaskShape) -> MaskShape {
                var out = shape
                guard index < out.vertices.count else { return out }
                out.vertices.remove(at: index)
                return out
            }
            if let shape = clip.mask { clip.mask = removed(shape) }
            if clip.maskTrack?.isActive == true {
                for i in clip.maskTrack!.keyframes.indices {
                    clip.maskTrack!.keyframes[i].value = removed(clip.maskTrack!.keyframes[i].value)
                }
            }
        }
    }

    func setMaskFeather(clipId: String, feather: Double, commit: Bool) {
        let value = min(1, max(0, feather))
        let write: (inout Clip) -> Void = { clip in
            // Feather is a look, not a shape: it stays on the static value even while
            // the path animates, so scrubbing cannot change the softness.
            guard var shape = clip.mask ?? clip.maskTrack?.keyframes.first?.value else { return }
            shape.feather = value
            clip.mask = shape
        }
        if commit {
            commitClipProperty(clipId: clipId, actionName: "Change Mask Feather", write)
        } else {
            applyClipProperty(clipId: clipId, write)
        }
    }

    func setMaskInverted(clipId: String, inverted: Bool) {
        commitClipProperty(clipId: clipId, actionName: inverted ? "Invert Mask" : "Un-invert Mask") { clip in
            guard var shape = clip.mask ?? clip.maskTrack?.keyframes.first?.value else { return }
            shape.inverted = inverted
            clip.mask = shape
        }
    }

    /// Commit the pen tool's draft as the clip's mask.
    func commitMaskDraft(clipId: String, points: [CGPoint]) {
        guard points.count >= 3 else { return }
        let shape = MaskShape(vertices: points.map { MaskVertex(x: Double($0.x), y: Double($0.y)) })
        setMaskShape(clipId: clipId, shape: shape, actionName: "Draw Mask")
    }
}
