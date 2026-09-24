import SwiftUI

struct ViewSkillsButton: View {
    var accessibilityID: String? = nil

    var body: some View {
        Button(action: openSkills) {
            Image(systemName: "book.closed")
                .font(.system(size: AppTheme.FontSize.sm, weight: .medium))
                .foregroundStyle(AppTheme.Text.tertiaryColor)
                .frame(width: AppTheme.IconSize.smMd, height: AppTheme.IconSize.smMd)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(L10n.string("View Skills"))
        .accessibilityLabel(L10n.string("View Skills"))
        .accessibilityIdentifier(accessibilityID ?? "")
        .tourAnchor(.skillsButton)
    }

    private func openSkills() {
        SettingsWindowController.shared.show(tab: .skills)
    }
}
