import MCP

extension ToolName {
    /// Exhaustive so a new tool cannot reach MCP clients without a declared risk.
    var mcpAnnotations: Tool.Annotations {
        switch self {
        case .getTimeline, .inspectTimeline, .getMedia, .inspectMedia, .searchMedia,
             .getMulticam, .getTranscript, .detectBeats, .inspectColor, .listModels, .readSkill:
            return .read
        case .listSources, .listSourceAssets:
            return .readExternal
        case .setActiveTimeline, .setProjectSettings, .setClipProperties, .setMask:
            return .edit(idempotent: true)
        case .manageProject, .createTimeline, .manageExports, .captureFrame, .manageClipLinks,
             .insertClips, .splitClips, .copyClipSettings, .setKeyframes, .applyLayout, .syncClips,
             .undo, .manageMulticam, .changeCam, .addTexts, .updateText, .addCaptions,
             .applyColor, .applyEffect, .denoiseAudio, .trackSubject:
            return .edit(idempotent: false)
        case .manageMarkers, .manageTracks, .organizeMedia, .addClips, .duplicateClips, .moveClips, .removeClips,
             .rippleDeleteRanges, .swapClipMedia, .removeWords, .removeSilence, .manageSkills:
            return .destructive
        case .importMedia, .importSourceAsset, .exportProject, .sendFeedback,
             .generateVideo, .generateImage, .generateAudio, .upscaleMedia:
            return .external
        }
    }
}

private extension Tool.Annotations {
    // MCP defaults destructiveHint and openWorldHint to true, so every hint is stated.
    static let read = Tool.Annotations(
        readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false)
    static let readExternal = Tool.Annotations(
        readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: true)
    static let destructive = Tool.Annotations(
        readOnlyHint: false, destructiveHint: true, idempotentHint: false, openWorldHint: false)

    static func edit(idempotent: Bool) -> Tool.Annotations {
        Tool.Annotations(
            readOnlyHint: false, destructiveHint: false, idempotentHint: idempotent, openWorldHint: false)
    }

    static let external = Tool.Annotations(
        readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: true)
}
