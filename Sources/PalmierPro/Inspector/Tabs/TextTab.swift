import AppKit
import SwiftUI

struct TextTab: View {
    let clips: [Clip]
    @Environment(EditorViewModel.self) private var editor

    private static let defaults = TextStyle()

    private var clip: Clip { clips[0] }
    private var clipIds: [String] { clips.map(\.id) }
    private var isBatch: Bool { clips.count > 1 }

    private var fillMode: TextFillMode? {
        sharedClipValue(clips) { $0.textFillMode ?? .color }
    }

    private var styleDefaults: TextStyle {
        var defaults = Self.defaults
        if fillMode == .footage {
            defaults.color = TextFillMode.defaultFootageMatteColor
        }
        return defaults
    }

    private var showsColorControl: Bool {
        guard let fillMode else { return false }
        return fillMode != .inverted
    }

    private var showsSolidFillControls: Bool {
        fillMode == .color
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.zero) {
            contentField
            Button(L10n.string("Import…"), action: importTextEffect)
                .accessibilityIdentifier("inspector.text.import")
            TextStyleControls(
                selection: TextStyleSelection(
                    styles: clips.map { $0.textStyle ?? styleDefaults },
                    fallback: styleDefaults
                ),
                defaults: styleDefaults,
                showsColorControl: showsColorControl,
                showsSolidFillControls: showsSolidFillControls,
                keyframeClips: clips,
                accessibilityID: "inspector.textStyle",
                actions: styleActions,
                afterAlignment: {
                    positionSection
                    tiltSection
                    rotationSection
                    fillModeRow
                },
                afterColor: { opacitySlider }
            )
        }
    }

    private func importTextEffect() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        let projectId = editor.projectId
        let timeline = editor.timeline
        let ids = clipIds
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task {
                do {
                    let definition = try await Task.detached(priority: .userInitiated) {
                        try EffectPackage.textStyle(in: url)
                    }.value
                    guard editor.projectId == projectId, editor.timeline == timeline else {
                        throw LUTStoreError.invalid("The timeline changed during effect import; try again")
                    }
                    editor.commitTextStyles(clipIds: ids) { style in
                        definition.apply(to: &style)
                    }
                } catch { NSAlert(error: error).runModal() }
            }
        }
    }

    private var fillModeRow: some View {
        let current = sharedClipValue(clips) { $0.textFillMode ?? .color }
        return InspectorRow(
            label: L10n.string("Fill"),
            accessibilityID: "inspector.text.fill",
            onReset: {
                editor.commitClipProperties(clipIds: clipIds) { $0.setTextFillMode(.color) }
            }
        ) {
            Menu {
                ForEach(TextFillMode.allCases, id: \.self) { mode in
                    Button(L10n.string(key: mode.displayName)) {
                        editor.commitClipProperties(clipIds: clipIds) {
                            $0.setTextFillMode(mode)
                        }
                    }
                    .accessibilityIdentifier("inspector.text.fill.\(mode.rawValue)")
                }
            } label: {
                EditorMenuValue(text: current.map { L10n.string(key: $0.displayName) } ?? "—")
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize().focusable(false)
            .accessibilityLabel(L10n.string("Fill"))
            .accessibilityIdentifier("inspector.text.fill")
        }
    }

    private var contentField: some View {
        EditorPanelGroup(L10n.string("Text"), accessibilityID: "inspector.text") {
            TextContentField(
                text: Binding(
                    get: { clip.textContent ?? "" },
                    set: { new in
                        guard !isBatch else { return }
                        editor.applyTextContent(clipId: clip.id, content: new)
                    }
                ),
                onCommit: { new in
                    guard !isBatch else { return }
                    editor.commitTextContent(clipId: clip.id, content: new)
                }
            )
            .disabled(isBatch)
            .opacity(isBatch ? AppTheme.Opacity.medium : AppTheme.Opacity.opaque)
            .frame(minHeight: AppTheme.EditorPanel.textEditorMinHeight)
            .padding(AppTheme.Spacing.smMd)
            .editorValueField()
        }
    }

    private var opacitySlider: some View {
        InspectorRow(
            label: L10n.string("Opacity"),
            accessibilityID: "inspector.text.opacity",
            onReset: {
                editor.commitClipProperties(clipIds: clipIds) {
                    $0.opacity = 1
                    $0.opacityTrack = nil
                }
            }
        ) {
            KeyframePropertyValueFields(
                clips: clips,
                property: .opacity,
                style: .inspector,
                accessibilityID: "inspector.text.opacity"
            )
        }
    }

    @ViewBuilder
    private var positionSection: some View {
        InspectorRow(
            label: L10n.string("Position"),
            accessibilityID: "inspector.text.position",
            onReset: {
                editor.commitClipProperties(clipIds: clipIds) {
                    $0.transform.centerX = Transform().centerX
                    $0.transform.centerY = Transform().centerY
                    $0.positionTrack = nil
                }
            }
        ) {
            KeyframePropertyValueFields(
                clips: clips,
                property: .position,
                style: .inspector,
                accessibilityID: "inspector.text.position"
            )
        }
    }

    private var tiltSection: some View {
        InspectorRow(
            label: L10n.string("Tilt"),
            accessibilityID: "inspector.text.tilt",
            onReset: {
                editor.commitClipProperties(clipIds: clipIds, actionName: "Reset Text Tilt") {
                    $0.transform.rotationX = 0
                    $0.transform.rotationY = 0
                }
            }
        ) {
            HStack(spacing: AppTheme.Spacing.sm) {
                tiltField("X", keyPath: \.rotationX, accessibilityID: "inspector.text.tilt.x")
                tiltField("Y", keyPath: \.rotationY, accessibilityID: "inspector.text.tilt.y")
            }
            .fixedSize()
        }
    }

    private func tiltField(
        _ axis: String,
        keyPath: WritableKeyPath<Transform, Double>,
        accessibilityID: String
    ) -> some View {
        ScrubbableNumberField(
            value: sharedClipValue(clips) { $0.transform[keyPath: keyPath] },
            range: Transform.tiltRotationRange,
            format: "%.0f",
            valueSuffix: "°",
            fieldWidth: AppTheme.EditorPanel.compactNumericFieldWidth,
            trailingLabel: axis,
            onChanged: { value in
                editor.applyClipProperties(clipIds: clipIds) {
                    $0.transform[keyPath: keyPath] = value
                }
            }
        ) { value in
            editor.commitClipProperties(clipIds: clipIds, actionName: "Change Text Tilt") {
                $0.transform[keyPath: keyPath] = value
            }
        }
        .accessibilityLabel(Text(verbatim: "\(L10n.string("Tilt")) \(axis)"))
        .accessibilityIdentifier(accessibilityID)
    }

    private var rotationSection: some View {
        InspectorRow(
            label: L10n.string("Rotation"),
            accessibilityID: "inspector.text.rotation",
            onReset: {
                editor.commitClipProperties(clipIds: clipIds, actionName: "Reset Rotation") {
                    $0.transform.rotation = Transform().rotation
                    $0.rotationTrack = nil
                }
            }
        ) {
            KeyframePropertyValueFields(
                clips: clips,
                property: .rotation,
                style: .inspector,
                accessibilityID: "inspector.text.rotation"
            )
        }
    }

    private var styleActions: TextStyleEditingActions {
        TextStyleEditingActions(
            apply: { fitToContent, mutation in
                editor.applyTextStyles(
                    clipIds: clipIds,
                    fitToContent: fitToContent,
                    mutation
                )
            },
            commit: { fitToContent, mutation in
                editor.commitTextStyles(
                    clipIds: clipIds,
                    fitToContent: fitToContent,
                    mutation
                )
            },
            commitColor: { key, mutation in
                editor.debouncedCommitTextStyles(clipIds: clipIds, key: key, mutation)
            },
            cancelPending: { editor.cancelDebouncedCommit(key: $0) },
            cancelFontPreview: { _ in
                editor.revertClipProperties(clipIds: clipIds)
            }
        )
    }
}

struct TextAnimateTab: View {
    let clips: [Clip]
    @Environment(EditorViewModel.self) private var editor

    private var clip: Clip { clips[0] }
    private var targetIds: [String] {
        editor.captionGroupTextClipIds(expanding: clips.map(\.id))
    }

    var body: some View {
        let anim = clip.textAnimation ?? TextAnimation()
        EditorPanelGroup(L10n.string("Animation"), accessibilityID: "inspector.textAnimation") {
            CaptionPresetGallery(
                selection: Binding(
                    get: { anim.preset },
                    set: { new in setAnim { $0.preset = new } }
                ),
                highlight: anim.highlight
            )
            if anim.preset.usesHighlight { highlightRow(anim) }
        }
    }

    private func setAnim(_ modify: (inout TextAnimation) -> Void) {
        var a = clip.textAnimation ?? TextAnimation()
        modify(&a)
        let value: TextAnimation? = a.preset == .none ? nil : a
        editor.cancelDebouncedCommit(key: "textHighlight")
        editor.commitClipProperties(clipIds: targetIds) { $0.textAnimation = value }
    }

    private func highlightRow(_ anim: TextAnimation) -> some View {
        InspectorRow(
            label: L10n.string("Highlight"),
            accessibilityID: "inspector.textAnimation.highlight",
            onReset: {
                editor.cancelDebouncedCommit(key: "textHighlight")
                editor.commitClipProperties(clipIds: targetIds) {
                    guard var animation = $0.textAnimation else { return }
                    animation.highlight = TextAnimation.defaultHighlight
                    $0.textAnimation = animation
                }
            }
        ) {
            ColorField(
                displayColor: (anim.highlight ?? TextAnimation.defaultHighlight).swiftUIColor,
                onUserChange: { new in
                    editor.debouncedCommitClipProperties(clipIds: targetIds, key: "textHighlight") {
                        guard var a = $0.textAnimation, a.preset.usesHighlight else { return }
                        a.highlight = TextStyle.RGBA(new)
                        $0.textAnimation = a
                    }
                }
            )
            .accessibilityLabel(L10n.string("Highlight"))
            .accessibilityIdentifier("inspector.textAnimation.highlight")
        }
    }
}
