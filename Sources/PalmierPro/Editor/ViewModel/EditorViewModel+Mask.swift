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

    func setMaskEnabled(clipId: String, enabled: Bool) {
        commitClipProperty(clipId: clipId, actionName: "Toggle Mask") { $0.maskEnabled = enabled }
        if !enabled { maskEditingActive = false }
    }

    func beginMaskEditing(clipId: String, linear: Bool) {
        commitClipProperty(clipId: clipId, actionName: "Change Mask Shape") { clip in
            clip.mask = linear ? MaskShape(linear: .init()) : nil
            clip.maskTrack = nil
            clip.maskEnabled = true
        }
        cropEditingActive = false
        maskEditingActive = true
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

    func setLinearMaskValue(clipId: String, keyPath: WritableKeyPath<LinearMaskGeometry, Double>, value: Double) {
        guard value.isFinite, let clip = clipFor(id: clipId),
              var shape = clip.maskAt(frame: activeFrame), shape.linear != nil else { return }
        shape.linear?[keyPath: keyPath] = value
        setMaskShape(clipId: clipId, shape: shape, actionName: "Change Linear Mask")
    }

    func setMaskFeather(clipId: String, feather: Double, commit: Bool) {
        guard feather.isFinite else { return }
        let value = min(1, max(0, feather))
        guard let clip = clipFor(id: clipId), var shape = clip.maskAt(frame: activeFrame) else { return }
        shape.feather = value
        if commit { commitMaskShape(clipId: clipId, shape: shape, actionName: "Change Mask Feather") }
        else { applyMaskShape(clipId: clipId, shape: shape) }
    }

    func setMaskInverted(clipId: String, inverted: Bool) {
        guard let clip = clipFor(id: clipId), var shape = clip.maskAt(frame: activeFrame) else { return }
        shape.inverted = inverted
        setMaskShape(clipId: clipId, shape: shape, actionName: "Invert Mask")
    }

    /// Commit the pen tool's draft as the clip's mask.
    func commitMaskDraft(clipId: String, points: [CGPoint]) {
        guard points.count >= 3 else { return }
        let shape = MaskShape(vertices: points.map { MaskVertex(x: Double($0.x), y: Double($0.y)) })
        setMaskShape(clipId: clipId, shape: shape, actionName: "Draw Mask")
    }
}
