import SwiftUI

struct LinearMaskControls: View {
    @Environment(EditorViewModel.self) var editor
    let clip: Clip

    var body: some View {
        if let shape = clip.maskAt(frame: editor.activeFrame), let linear = shape.linear {
            VStack(spacing: AppTheme.Spacing.sm) {
                HStack {
                    Text(L10n.string("Position"))
                    Spacer()
                    field(linear.centerX, range: -2...2, label: "X") {
                        editor.setLinearMaskValue(clipId: clip.id, keyPath: \.centerX, value: $0)
                    }
                    field(linear.centerY, range: -2...2, label: "Y") {
                        editor.setLinearMaskValue(clipId: clip.id, keyPath: \.centerY, value: $0)
                    }
                }
                HStack {
                    Text(L10n.string("Rotation"))
                    Spacer()
                    ScrubbableNumberField(value: linear.rotation, range: -180...180, valueSuffix: "°") {
                        editor.setLinearMaskValue(clipId: clip.id, keyPath: \.rotation, value: $0)
                    }
                }
            }
            .font(.system(size: AppTheme.FontSize.sm))
        }
    }

    private func field(_ value: Double, range: ClosedRange<Double>, label: String,
                       commit: @escaping (Double) -> Void) -> some View {
        ScrubbableNumberField(value: value, range: range, format: "%.2f",
                              dragSensitivity: 0.01, trailingLabel: label, onCommit: commit)
    }
}
