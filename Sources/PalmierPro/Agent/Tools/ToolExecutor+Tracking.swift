import Foundation

extension ToolExecutor {

    func trackSubject(_ editor: EditorViewModel, _ args: [String: Any]) async throws -> ToolResult {
        try validateUnknownKeys(
            args,
            allowed: ["clipId", "sourceClipId", "mode", "startFrame", "endFrame", "minConfidence", "step", "phaseShapes", "hideWhenClosed"],
            path: "track_subject"
        )
        let clipId = try args.requireString("clipId")
        guard let clip = await editor.clipFor(id: clipId) else {
            throw ToolError("Clip not found: \(clipId)")
        }
        let rawMode = (args["mode"] as? String) ?? "hands"
        guard let mode = EditorViewModel.TrackingMode(rawValue: rawMode) else {
            throw ToolError("mode: expected 'hands' or 'region' (got '\(rawMode)')")
        }

        var range: ClosedRange<Int>?
        if args["startFrame"] != nil || args["endFrame"] != nil {
            let start = (args["startFrame"] as? Int) ?? clip.startFrame
            let end = (args["endFrame"] as? Int) ?? clip.endFrame
            guard start < end else {
                throw ToolError("startFrame (\(start)) must be less than endFrame (\(end)).")
            }
            range = start...(end - 1)
        }
        let minConfidence = (args["minConfidence"] as? Double) ?? 0.3
        guard (0...1).contains(minConfidence) else {
            throw ToolError("minConfidence: must be between 0 and 1 (got \(minConfidence))")
        }
        let step = (args["step"] as? Int) ?? 1
        guard step >= 1, step <= 30 else {
            throw ToolError("step: must be between 1 and 30 (got \(step))")
        }

        let sourceClipId = args["sourceClipId"] as? String
        if let sourceClipId, await editor.clipFor(id: sourceClipId) == nil {
            throw ToolError("Clip not found: \(sourceClipId)")
        }
        var phaseShapes: [[Int]]?
        if let raw = args["phaseShapes"] {
            guard let list = raw as? [Any], !list.isEmpty else {
                throw ToolError("phaseShapes: expected a non-empty array of vertex orders.")
            }
            var parsed: [[Int]] = []
            for (i, entry) in list.enumerated() {
                guard let order = entry as? [Any] else {
                    throw ToolError("phaseShapes[\(i)]: expected an array of point indices, e.g. [0, 1, 3, 2]")
                }
                let ints = order.compactMap { $0 as? Int }
                guard ints.count == order.count else {
                    throw ToolError("phaseShapes[\(i)]: every entry must be an integer point index.")
                }
                guard ints.count == 4, ints.allSatisfy({ (0..<4).contains($0) }) else {
                    throw ToolError(
                        "phaseShapes[\(i)]: expected 4 indices, each 0–3, over the tracked corners "
                        + "ordered clockwise from the centre. Got \(ints)."
                    )
                }
                parsed.append(ints)
            }
            phaseShapes = parsed
        }
        let result: EditorViewModel.TrackingResult
        do {
            result = try await editor.trackSubject(
                clipId: clipId, mode: mode, sourceClipId: sourceClipId, range: range,
                minimumConfidence: minConfidence, step: step, phaseShapes: phaseShapes,
                hideWhenClosed: (args["hideWhenClosed"] as? Bool) ?? true
            )
        } catch let error as LocalizedError {
            throw ToolError(error.errorDescription ?? "Tracking failed.")
        }

        var out: [String: Any] = [
            "clipId": clipId,
            "mode": mode.rawValue,
            "sourceClipId": sourceClipId ?? clipId,
            "keyframes": result.keyframesWritten,
        ]
        var notes: [String] = []
        if let r = result.trackedRange { out["trackedFrames"] = [r.lowerBound, r.upperBound + 1] }
        if !result.phaseBoundaries.isEmpty {
            out["phaseBoundaries"] = result.phaseBoundaries
            notes.append(
                "The hands came together at \(result.phaseBoundaries.map(String.init).joined(separator: ", ")) — "
                + "\(result.phaseBoundaries.count + 1) phases. Pass phaseShapes to give each phase its own vertex order."
            )
        }
        if let lost = result.lostAtFrame {
            out["lostAtFrame"] = lost
            notes.append(
                "Tracking stopped at frame \(lost): confidence fell below \(minConfidence). "
                + "Frames after it were left untracked rather than extrapolated. "
                + "Re-run from that frame after correcting the mask, or lower minConfidence to accept a looser track."
            )
        }
        if !result.skippedFrames.isEmpty {
            out["skippedFrames"] = result.skippedFrames.count
            notes.append("\(result.skippedFrames.count) frame(s) had no usable detection and were interpolated across.")
        }
        if !notes.isEmpty { out["notes"] = notes }
        return .ok(Self.jsonString(out) ?? "{}")
    }
}
