import SwiftUI

struct MaskInspectorSection: View {
    @Environment(EditorViewModel.self) private var editor
    let clip: Clip?
    @State private var featherEditing = false
    @State private var featherValue = 0.0

    var body: some View {
        EditorPanelGroup(L10n.string("Mask"), onReset: {
            if let clip { editor.clearMask(clipId: clip.id); editor.maskEditingActive = false }
        }, headerAccessory: {
            Toggle(L10n.string("Enable Mask"), isOn: Binding(
                get: { clip?.hasMask == true && clip?.maskEnabled == true },
                set: { enabled in
                    guard let clip else { return }
                    if enabled && !clip.hasMask { editor.beginMaskEditing(clipId: clip.id, linear: true) }
                    else { editor.setMaskEnabled(clipId: clip.id, enabled: enabled) }
                }))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(clip == nil)
        }) {
            if let clip {
                let shape = clip.maskAt(frame: editor.activeFrame)
                HStack(spacing: AppTheme.Spacing.sm) {
                    shapeButton(L10n.key("Linear Mask"), symbol: "rectangle.split.1x2", selected: shape?.linear != nil) {
                        if shape?.linear != nil {
                            editor.setMaskEnabled(clipId: clip.id, enabled: true)
                            editor.cropEditingActive = false
                            editor.maskEditingActive = true
                        } else { editor.beginMaskEditing(clipId: clip.id, linear: true) }
                    }
                    shapeButton(L10n.key("Path Mask"), symbol: "point.topleft.down.to.point.bottomright.curvepath",
                                selected: shape?.linear == nil && (shape != nil || editor.maskEditingActive)) {
                        if shape != nil && shape?.linear == nil {
                            editor.setMaskEnabled(clipId: clip.id, enabled: true)
                            editor.cropEditingActive = false
                            editor.maskEditingActive = true
                        } else { editor.beginMaskEditing(clipId: clip.id, linear: false) }
                    }
                }
                if let shape {
                    VStack(spacing: AppTheme.Spacing.smMd) {
                        HStack {
                            Text(L10n.string("Mask Parameters"))
                            Spacer()
                            InspectorKeyframeControls(clipId: clip.id, property: .mask)
                        }
                        if shape.linear != nil { LinearMaskControls(clip: clip) }
                        HStack {
                            Text(L10n.string("Feather"))
                            Slider(value: Binding(get: { featherEditing ? featherValue : shape.feather }, set: { value in
                                featherValue = value
                                editor.setMaskFeather(clipId: clip.id, feather: value, commit: false)
                            }), in: 0...1, onEditingChanged: { editing in
                                featherEditing = editing
                                if editing { featherValue = shape.feather }
                                else { editor.setMaskFeather(clipId: clip.id, feather: featherValue, commit: true) }
                            })
                            .accessibilityLabel(L10n.string("Mask Feather"))
                            ScrubbableNumberField(value: shape.feather, range: 0...1,
                                displayMultiplier: 100, valueSuffix: "%") {
                                editor.setMaskFeather(clipId: clip.id, feather: $0, commit: true)
                            }
                        }
                        Toggle(L10n.string("Invert (Keep Outside)"), isOn: Binding(
                            get: { shape.inverted },
                            set: { editor.setMaskInverted(clipId: clip.id, inverted: $0) }))
                            .toggleStyle(.checkbox)
                        HStack {
                            Button(editor.maskEditingActive ? L10n.string("Done") : L10n.string("Edit on Canvas")) {
                                editor.cropEditingActive = false
                                editor.maskEditingActive.toggle()
                            }
                            Spacer()
                            Menu(L10n.string("Tracking")) {
                                Button("Track Hands") { Task { await editor.runSubjectTracking(clipId: clip.id, mode: .hands) } }
                                Button("Track This Mask") { Task { await editor.runSubjectTracking(clipId: clip.id, mode: .region) } }
                                    .disabled(shape.linear != nil)
                            }
                            .disabled(editor.trackingClipId != nil)
                        }
                    }
                    .disabled(!clip.maskEnabled)
                    .opacity(clip.maskEnabled ? 1 : 0.5)
                } else {
                    Text(L10n.string(editor.maskEditingActive
                        ? "Click on the canvas to draw a path. Click the first point to close."
                        : "Choose a mask shape to begin."))
                        .foregroundStyle(AppTheme.Text.secondaryColor)
                }
            } else {
                Text(L10n.string("Mask applies to one clip at a time"))
                    .foregroundStyle(AppTheme.Text.secondaryColor)
            }
        }
        .font(.system(size: AppTheme.FontSize.sm))
        .onDisappear {
            if featherEditing, let clip {
                editor.setMaskFeather(clipId: clip.id, feather: featherValue, commit: true)
            }
        }
    }

    private func shapeButton(_ title: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: symbol).font(.title2)
                Text(L10n.string(key: title)).font(.system(size: AppTheme.FontSize.sm))
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(selected ? AppTheme.Accent.timecodeColor.opacity(0.15) : AppTheme.Background.baseColor)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(
                selected ? AppTheme.Accent.timecodeColor : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
