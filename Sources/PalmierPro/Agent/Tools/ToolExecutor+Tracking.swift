import Foundation

extension ToolExecutor {

    func trackSubject(_ editor: EditorViewModel, _ args: [String: Any]) async throws -> ToolResult {
        try validateUnknownKeys(
            args,
            allowed: ["clipId", "sourceClipId", "mode", "startFrame", "endFrame", "minConfidence", "step"],
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
        let result: EditorViewModel.TrackingResult
        do {
            result = try await editor.trackSubject(
                clipId: clipId, mode: mode, sourceClipId: sourceClipId, range: range,
                minimumConfidence: minConfidence, step: step
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
        if let r = result.trackedRange { out["trackedFrames"] = [r.lowerBound, r.upperBound + 1] }
        var notes: [String] = []
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
