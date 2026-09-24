import SwiftUI

struct KeyframeControlStrip: View {
    let previousAction: (() -> Void)?
    let keyframeAction: (() -> Void)?
    let nextAction: (() -> Void)?
    let isOnKeyframe: Bool
    let hasKeyframes: Bool
    let unavailableKeyframeHelp: String
    /// Base identifier; the buttons append `.previousKeyframe`, `.keyframe`, and `.nextKeyframe`.
    var accessibilityID: String? = nil

    static var width: CGFloat {
        AppTheme.EditorPanel.fieldMinHeight + AppTheme.Spacing.sm * 2
    }

    private var keyframeColor: Color {
        isOnKeyframe || hasKeyframes ? AppTheme.Accent.timecodeColor : AppTheme.Text.tertiaryColor
    }

    private var keyframeHelp: String {
        guard keyframeAction != nil else { return unavailableKeyframeHelp }
        return isOnKeyframe ? L10n.string("Delete keyframe") : L10n.string("Add keyframe")
    }

    var body: some View {
        HStack(spacing: AppTheme.Spacing.zero) {
            navigationButton(
                systemName: "chevron.left",
                action: previousAction,
                help: L10n.string("Go to previous keyframe"),
                identifierSuffix: "previousKeyframe"
            )
            Button(action: { keyframeAction?() }) {
                Image(systemName: isOnKeyframe ? "diamond.fill" : "diamond")
                    .font(.system(size: AppTheme.FontSize.xs, weight: AppTheme.FontWeight.medium))
                    .foregroundStyle(keyframeColor)
                    .frame(width: AppTheme.EditorPanel.fieldMinHeight, height: AppTheme.EditorPanel.fieldMinHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(keyframeAction == nil)
            .opacity(keyframeAction == nil ? AppTheme.Opacity.strong : AppTheme.Opacity.opaque)
            .help(keyframeHelp)
            .accessibilityLabel(keyframeHelp)
            .accessibilityIdentifier(accessibilityID.map { "\($0).keyframe" } ?? "")
            navigationButton(
                systemName: "chevron.right",
                action: nextAction,
                help: L10n.string("Go to next keyframe"),
                identifierSuffix: "nextKeyframe"
            )
        }
        .fixedSize()
    }

    private func navigationButton(
        systemName: String,
        action: (() -> Void)?,
        help: String,
        identifierSuffix: String
    ) -> some View {
        Button(action: { action?() }) {
            Image(systemName: systemName)
                .font(.system(size: AppTheme.FontSize.xxs, weight: AppTheme.FontWeight.semibold))
                .foregroundStyle(AppTheme.Text.tertiaryColor)
                .frame(width: AppTheme.Spacing.sm, height: AppTheme.EditorPanel.fieldMinHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
        .opacity(action == nil ? AppTheme.Opacity.strong : AppTheme.Opacity.opaque)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityIdentifier(accessibilityID.map { "\($0).\(identifierSuffix)" } ?? "")
    }
}
