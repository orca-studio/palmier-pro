import Foundation

fileprivate struct DuplicateClipsInput: DecodableToolArgs {
    let clipIds: [String]
    let startFrame: Int?
    let placement: String?
    static let allowedKeys: Set<String> = ["clipIds", "startFrame", "placement"]
}

extension ToolExecutor {
    func duplicateClips(_ editor: EditorViewModel, _ args: [String: Any]) throws -> ToolResult {
        let input: DuplicateClipsInput = try decodeToolArgs(args, path: "duplicate_clips")
        guard !input.clipIds.isEmpty else { throw ToolError("Provide a non-empty 'clipIds' array") }
        let placementRaw = input.placement ?? ClipDuplicatePlacement.newTracks.rawValue
        guard let placement = ClipDuplicatePlacement(rawValue: placementRaw) else {
            throw ToolError("placement must be 'newTracks' or 'sameTracks' (got '\(placementRaw)')")
        }
        for id in input.clipIds where editor.findClip(id: id) == nil {
            throw ToolError("Clip not found: \(id)")
        }

        let requested = Set(input.clipIds)
        let expanded = editor.expandToLinkGroup(requested)
        let sources = expanded.compactMap { editor.clipFor(id: $0) }
        let earliest = sources.map(\.startFrame).min() ?? 0
        let latestEnd = sources.map(\.endFrame).max() ?? 0

        var frameDelta = 0
        if let startFrame = input.startFrame {
            guard startFrame >= 0 else { throw ToolError("startFrame must be >= 0 (got \(startFrame))") }
            let shifted = latestEnd.addingReportingOverflow(startFrame - earliest)
            guard !shifted.overflow, startFrame - earliest < Int(Int32.max) else {
                throw ToolError("startFrame \(startFrame) is out of range")
            }
            frameDelta = startFrame - earliest
        }

        if placement == .sameTracks {
            guard frameDelta != 0 else {
                throw ToolError("placement 'sameTracks' needs a startFrame that moves the copies away from the originals; use 'newTracks' to stack copies over them.")
            }
            let sourceIds = Set(sources.map(\.id))
            for source in sources {
                guard let loc = editor.findClip(id: source.id) else { continue }
                let copyRange = (source.startFrame + frameDelta)..<(source.endFrame + frameDelta)
                let clobbered = editor.timeline.tracks[loc.trackIndex].clips.first {
                    sourceIds.contains($0.id) && copyRange.overlaps($0.startFrame..<$0.endFrame)
                }
                if let clobbered {
                    throw ToolError("The copy of \(source.id) would overwrite \(clobbered.id), which is being duplicated. Move startFrame past the originals or use 'newTracks'.")
                }
            }
        }

        let snapshot = timelineSnapshot(editor)
        let actionName = expanded.count == 1 ? "Duplicate Clip (Agent)" : "Duplicate Clips (Agent)"
        let copies = editor.duplicateClips(
            sources.map(\.id), frameDelta: frameDelta, placement: placement, actionName: actionName
        )
        guard copies.count == sources.count else {
            throw ToolError("Duplicated \(copies.count) of \(sources.count) clips; the rest had no compatible destination.")
        }

        var notes: [String] = []
        let partners = expanded.subtracting(requested).sorted()
        if !partners.isEmpty {
            notes.append("Linked partners were duplicated too so the copies stay linked: \(partners.joined(separator: ", ")).")
        }
        let pairs = copies.keys.sorted().map { ["sourceClipId": $0, "clipId": copies[$0]!] }
        return mutationResult(editor, since: snapshot, extra: ["copies": pairs], notes: notes)
    }
}
