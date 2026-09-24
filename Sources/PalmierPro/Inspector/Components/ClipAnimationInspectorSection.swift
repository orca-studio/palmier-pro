import SwiftUI

struct ClipAnimationInspectorSection: View {
    @Environment(EditorViewModel.self) private var editor
    let clips: [Clip]
    @State private var isExpanded = true

    static let defaultDurationSeconds = 0.5

    var body: some View {
        if !clips.isEmpty {
            EditorPanelGroup(
                L10n.string("Animation"),
                isExpanded: $isExpanded,
                onReset: {
                    commit("Reset Animation") {
                        $0.inAnimation = nil
                        $0.outAnimation = nil
                    }
                }
            ) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.smMd) {
                    presetRow(.left)
                    durationRow(.left)
                    presetRow(.right)
                    durationRow(.right)
                }
            }
        }
    }

    private var fps: Double { Double(max(1, editor.timeline.fps)) }

    private func animation(of clip: Clip, _ edge: FadeEdge) -> ClipAnimation? {
        edge == .left ? clip.inAnimation : clip.outAnimation
    }

    private func setAnimation(_ animation: ClipAnimation?, on clip: inout Clip, _ edge: FadeEdge) {
        if edge == .left { clip.inAnimation = animation } else { clip.outAnimation = animation }
    }

    private func commit(_ actionName: String, _ modify: @escaping (inout Clip) -> Void) {
        editor.commitClipProperties(clipIds: clips.map(\.id), actionName: actionName, modify)
    }

    private func presetRow(_ edge: FadeEdge) -> some View {
        let current = sharedClipValue(clips) { animation(of: $0, edge)?.preset }
        let label = edge == .left ? L10n.string("In") : L10n.string("Out")
        let noRoom = clips.allSatisfy { $0.maxAnimationFrames(edge) < 1 }
        return InspectorRow(
            label: label,
            onReset: { commit("Remove Animation") { setAnimation(nil, on: &$0, edge) } }
        ) {
            Menu {
                Button(L10n.string("None")) {
                    commit("Remove Animation") { setAnimation(nil, on: &$0, edge) }
                }
                ForEach(ClipAnimation.Preset.allCases, id: \.self) { preset in
                    Button(L10n.string(key: preset.displayName)) {
                        let defaultFrames = Int((Self.defaultDurationSeconds * fps).rounded())
                        commit("Set Animation") { clip in
                            let frames = min(
                                animation(of: clip, edge)?.durationFrames ?? defaultFrames,
                                clip.maxAnimationFrames(edge)
                            )
                            guard frames >= 1 else { return }
                            setAnimation(ClipAnimation(preset: preset, durationFrames: frames), on: &clip, edge)
                        }
                    }
                }
            } label: {
                EditorMenuValue(text: menuText(current))
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize().focusable(false)
            .disabled(noRoom)
        }
        .frame(height: AppTheme.EditorPanel.fieldMinHeight)
    }

    private func menuText(_ current: ClipAnimation.Preset??) -> String {
        guard let current else { return "—" }
        guard let preset = current else { return L10n.string("None") }
        return L10n.string(key: preset.displayName)
    }

    @ViewBuilder
    private func durationRow(_ edge: FadeEdge) -> some View {
        let animated = clips.filter { animation(of: $0, edge) != nil }
        if !animated.isEmpty {
            let maxFrames = animated.map { $0.maxAnimationFrames(edge) }.min() ?? 1
            InspectorRow(label: L10n.string("Duration")) {
                ScrubbableNumberField(
                    value: sharedClipValue(animated) { Double(animation(of: $0, edge)?.durationFrames ?? 0) / fps },
                    range: (1 / fps)...(Double(max(1, maxFrames)) / fps),
                    format: "%.1f",
                    valueSuffix: "s",
                    dragSensitivity: 1 / fps,
                    onChanged: { seconds in
                        editor.applyClipProperties(clipIds: animated.map(\.id)) { resize(&$0, edge, seconds) }
                    }
                ) { seconds in
                    editor.commitClipProperties(clipIds: animated.map(\.id), actionName: "Change Animation Duration") {
                        resize(&$0, edge, seconds)
                    }
                }
            }
            .frame(height: AppTheme.EditorPanel.fieldMinHeight)
        }
    }

    private func resize(_ clip: inout Clip, _ edge: FadeEdge, _ seconds: Double) {
        guard seconds.isFinite, var current = animation(of: clip, edge) else { return }
        current.durationFrames = min(max(1, Int((seconds * fps).rounded())), clip.maxAnimationFrames(edge))
        guard current.durationFrames >= 1 else { return }
        setAnimation(current, on: &clip, edge)
    }
}
