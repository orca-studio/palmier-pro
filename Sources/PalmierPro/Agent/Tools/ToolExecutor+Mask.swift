import Foundation

// The static half of a clip's path mask. Animation lives in set_keyframes'
// `maskPath` property, mirroring how set_clip_properties and set_keyframes split
// a transform.
extension ToolExecutor {

    /// Vertices arrive as `[[x, y], ...]`, or as objects when a point carries bezier
    /// handles. Coordinates are 0–1 of the source's display box.
    static func maskVertices(_ raw: Any, path: String) throws -> [MaskVertex] {
        guard let list = raw as? [Any] else {
            throw ToolError("\(path): expected an array of vertices")
        }
        guard list.count >= 3 else {
            throw ToolError("\(path): a mask needs at least 3 vertices (got \(list.count))")
        }
        return try list.enumerated().map { i, entry in
            let at = "\(path)[\(i)]"
            if let pair = entry as? [Any] {
                guard pair.count == 2 else { throw ToolError("\(at): expected [x, y]") }
                return MaskVertex(
                    x: try normalized(pair[0], at: "\(at)[0] (x)"),
                    y: try normalized(pair[1], at: "\(at)[1] (y)")
                )
            }
            guard let obj = entry as? [String: Any] else {
                throw ToolError("\(at): expected [x, y] or {x, y, inControl?, outControl?}")
            }
            try validateUnknownKeys(obj, allowed: ["x", "y", "inControl", "outControl"], path: at)
            guard let rawX = obj["x"], let rawY = obj["y"] else {
                throw ToolError("\(at): requires 'x' and 'y'")
            }
            return MaskVertex(
                x: try normalized(rawX, at: "\(at).x"),
                y: try normalized(rawY, at: "\(at).y"),
                inControl: try control(obj["inControl"], at: "\(at).inControl"),
                outControl: try control(obj["outControl"], at: "\(at).outControl")
            )
        }
    }

    private static func control(_ raw: Any?, at path: String) throws -> AnimPair? {
        guard let raw else { return nil }
        guard let pair = raw as? [Any], pair.count == 2 else {
            throw ToolError("\(path): expected [dx, dy] offsets relative to the vertex")
        }
        // Handles may reach outside the source box; only finiteness matters.
        return AnimPair(
            a: try ToolExecutor.kfDouble(pair[0], at: "\(path)[0]"),
            b: try ToolExecutor.kfDouble(pair[1], at: "\(path)[1]")
        )
    }

    private static func normalized(_ raw: Any, at path: String) throws -> Double {
        let v = try ToolExecutor.kfDouble(raw, at: path)
        guard (-1.0...2.0).contains(v) else {
            throw ToolError("\(path): expected 0–1 of the source box (got \(v)); values far outside are almost always a coordinate-space mistake")
        }
        return v
    }

    func setMask(_ editor: EditorViewModel, _ args: [String: Any]) throws -> ToolResult {
        try validateUnknownKeys(args, allowed: ["clipIds", "vertices", "feather", "inverted", "remove"], path: "set_mask")
        guard let clipIds = args["clipIds"] as? [String], !clipIds.isEmpty else {
            throw ToolError("set_mask requires a non-empty 'clipIds' array.")
        }
        for id in clipIds where editor.findClip(id: id) == nil {
            throw ToolError("Clip not found: \(id)")
        }

        let removing = args["remove"] as? Bool == true
        if removing, args["vertices"] != nil {
            throw ToolError("set_mask: pass either 'remove' or 'vertices', not both.")
        }

        let vertices = try args["vertices"].map { try Self.maskVertices($0, path: "vertices") }
        let feather = try args["feather"].map { raw -> Double in
            let v = try ToolExecutor.kfDouble(raw, at: "feather")
            guard (0...1).contains(v) else { throw ToolError("feather: must be between 0 and 1 (got \(v))") }
            return v
        }
        let inverted = args["inverted"] as? Bool

        // Reject before mutating: changing the point count under a live track would
        // silently break every keyframe's correspondence.
        if let vertices {
            for id in clipIds {
                guard let clip = editor.clipFor(id: id), let track = clip.maskTrack, track.isActive else { continue }
                let existing = track.keyframes[0].value.vertices.count
                guard existing == vertices.count else {
                    throw ToolError(
                        "Clip \(id) has an animated mask with \(existing) vertices; "
                        + "set_mask cannot change the count to \(vertices.count). "
                        + "Replace the whole track with set_keyframes(property: 'maskPath'), or clear it first with remove:true."
                    )
                }
            }
        }

        guard removing || vertices != nil || feather != nil || inverted != nil else {
            throw ToolError("set_mask: nothing to change — pass vertices, feather, inverted, or remove.")
        }

        var changed = false
        editor.undo.perform("Set Mask (Agent)") {
            for id in clipIds {
                editor.commitClipProperty(clipId: id) { clip in
                    if removing {
                        if clip.mask != nil || clip.maskTrack != nil { changed = true }
                        clip.mask = nil
                        clip.maskTrack = nil
                        return
                    }
                    var shape = clip.mask ?? MaskShape()
                    if let vertices { shape.vertices = vertices }
                    if let feather { shape.feather = feather }
                    if let inverted { shape.inverted = inverted }
                    if clip.mask != shape { changed = true }
                    clip.mask = shape
                    // A live track owns the animated path; only the static fields carry over.
                    if let vertices, clip.maskTrack?.isActive == true {
                        for i in clip.maskTrack!.keyframes.indices {
                            clip.maskTrack!.keyframes[i].value.vertices = vertices
                        }
                    }
                }
            }
        }

        let receipts: [[String: Any]] = clipIds.compactMap { id -> [String: Any]? in
            guard let clip = editor.clipFor(id: id) else { return nil }
            var row: [String: Any] = ["clipId": id]
            if let mask = clip.mask, mask.isRenderable, !removing {
                row["mask"] = [
                    "vertexCount": mask.vertices.count,
                    "feather": mask.feather,
                    "inverted": mask.inverted,
                    "animated": clip.maskTrack?.isActive ?? false,
                ]
            } else {
                row["mask"] = NSNull()
            }
            return row
        }
        return .ok(Self.jsonString(["changed": changed, "clips": receipts]) ?? "{}")
    }
}
