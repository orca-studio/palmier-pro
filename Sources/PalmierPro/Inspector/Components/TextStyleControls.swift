import SwiftUI

struct TextStyleSelection {
    let styles: [TextStyle]
    let fallback: TextStyle

    var primary: TextStyle { styles.first ?? fallback }

    func value<Value: Equatable>(_ keyPath: KeyPath<TextStyle, Value>) -> Value? {
        guard let first = styles.first else { return fallback[keyPath: keyPath] }
        let value = first[keyPath: keyPath]
        return styles.dropFirst().allSatisfy { $0[keyPath: keyPath] == value } ? value : nil
    }
}

struct TextStyleEditingActions {
    typealias Mutation = (inout TextStyle) -> Void

    let apply: (_ fitToContent: Bool, _ mutation: @escaping Mutation) -> Void
    let commit: (_ fitToContent: Bool, _ mutation: @escaping Mutation) -> Void
    let commitColor: (_ key: String, _ mutation: @escaping Mutation) -> Void
    let cancelPending: (_ key: String) -> Void
    let cancelFontPreview: (_ originalFont: String?) -> Void
}

struct TextStyleControls<AfterAlignment: View, AfterColor: View>: View {
    let selection: TextStyleSelection
    let defaults: TextStyle
    let styleExpanded: Binding<Bool>?
    let showsColorControl: Bool
    let showsSolidFillControls: Bool
    let keyframeClips: [Clip]
    let accessibilityID: String?
    let actions: TextStyleEditingActions
    @ViewBuilder let afterAlignment: () -> AfterAlignment
    @ViewBuilder let afterColor: () -> AfterColor

    @Environment(EditorViewModel.self) private var editor
    @State private var outlineExpanded: Bool
    @State private var shadowExpanded: Bool
    @State private var backgroundExpanded: Bool

    init(
        selection: TextStyleSelection,
        defaults: TextStyle,
        styleExpanded: Binding<Bool>? = nil,
        groupsExpandedByDefault: Bool = true,
        showsColorControl: Bool = true,
        showsSolidFillControls: Bool = true,
        keyframeClips: [Clip] = [],
        accessibilityID: String? = nil,
        actions: TextStyleEditingActions,
        @ViewBuilder afterAlignment: @escaping () -> AfterAlignment,
        @ViewBuilder afterColor: @escaping () -> AfterColor
    ) {
        self.selection = selection
        self.defaults = defaults
        self.styleExpanded = styleExpanded
        self.showsColorControl = showsColorControl
        self.showsSolidFillControls = showsSolidFillControls
        self.keyframeClips = keyframeClips
        self.accessibilityID = accessibilityID
        self.actions = actions
        self.afterAlignment = afterAlignment
        self.afterColor = afterColor
        _outlineExpanded = State(initialValue: groupsExpandedByDefault)
        _shadowExpanded = State(initialValue: groupsExpandedByDefault)
        _backgroundExpanded = State(initialValue: groupsExpandedByDefault)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.zero) {
            EditorPanelGroup(L10n.string("Style"), accessibilityID: accessibilityID, isExpanded: styleExpanded) {
                fontRow
                traitsRow
                if keyframeClips.isEmpty {
                    numberRow(
                        label: L10n.string("Size"),
                        accessibilityIDSuffix: "size",
                        range: 12...300,
                        format: "%.0f",
                        suffix: " pt",
                        fitToContent: true,
                        keyPath: \.fontSize
                    )
                } else {
                    textSizeRow
                }
                numberRow(
                    label: L10n.string("Width"),
                    accessibilityIDSuffix: "width",
                    range: TextStyle.axisScaleRange,
                    displayMultiplier: 100,
                    format: "%.0f",
                    suffix: "%",
                    fitToContent: true,
                    keyPath: \.widthScale
                )
                numberRow(
                    label: L10n.string("Height"),
                    accessibilityIDSuffix: "height",
                    range: TextStyle.axisScaleRange,
                    displayMultiplier: 100,
                    format: "%.0f",
                    suffix: "%",
                    fitToContent: true,
                    keyPath: \.heightScale
                )
                numberRow(
                    label: L10n.string("Tracking"),
                    accessibilityIDSuffix: "tracking",
                    range: -20...100,
                    format: "%.1f",
                    suffix: " pt",
                    fitToContent: true,
                    keyPath: \.tracking
                )
                numberRow(
                    label: L10n.string("Line Spacing"),
                    accessibilityIDSuffix: "lineSpacing",
                    range: -100...300,
                    format: "%.1f",
                    suffix: " pt",
                    fitToContent: true,
                    keyPath: \.lineSpacing
                )
                fontCaseRow
                alignmentRow
                afterAlignment()
                if showsColorControl {
                    colorRow(
                        label: L10n.string("Color"),
                        debounceKey: "textColor",
                        accessibilityIDSuffix: "color",
                        keyPath: \.color
                    )
                }
                afterColor()
                numberRow(
                    label: L10n.string("Blur"),
                    accessibilityIDSuffix: "blur",
                    range: 0...100,
                    format: "%.0f",
                    suffix: " px",
                    keyPath: \.blur
                )
            }
            if showsSolidFillControls {
                outlineGroup
                shadowGroup
                backgroundGroup
            }
        }
    }

    private var fontRow: some View {
        let originalFont = selection.value(\.fontName)
        return InspectorRow(
            label: L10n.string("Font"),
            accessibilityID: elementID("font"),
            onReset: {
                actions.commit(true) { $0.fontName = defaults.fontName }
            }
        ) {
            FontPickerField(
                current: originalFont,
                onPreview: { name in
                    actions.apply(true) { $0.fontName = name }
                },
                onChange: { name in
                    actions.commit(true) { $0.fontName = name }
                },
                onCancel: {
                    actions.cancelFontPreview(originalFont)
                }
            )
            .accessibilityIdentifier(elementID("font") ?? "")
        }
    }

    private var traitsRow: some View {
        InspectorRow(
            label: L10n.string("Style"),
            accessibilityID: elementID("traits"),
            onReset: {
                actions.commit(true) {
                    $0.isBold = defaults.isBold
                    $0.isItalic = defaults.isItalic
                    $0.isUnderlined = defaults.isUnderlined
                    $0.isStruckThrough = defaults.isStruckThrough
                    $0.isOverlined = defaults.isOverlined
                }
            }
        ) {
            TextStyleTraitButtons(
                isBold: selection.value(\.isBold),
                isItalic: selection.value(\.isItalic),
                isUnderlined: selection.value(\.isUnderlined),
                isStruckThrough: selection.value(\.isStruckThrough),
                isOverlined: selection.value(\.isOverlined),
                onBold: { value in
                    actions.commit(true) { $0.isBold = value }
                },
                onItalic: { value in
                    actions.commit(true) { $0.isItalic = value }
                },
                onUnderline: { value in
                    actions.commit(false) { $0.isUnderlined = value }
                },
                onStrikethrough: { value in
                    actions.commit(false) { $0.isStruckThrough = value }
                },
                onOverline: { value in
                    actions.commit(false) { $0.isOverlined = value }
                },
                accessibilityID: elementID("traits")
            )
        }
    }

    private var fontCaseRow: some View {
        InspectorRow(
            label: L10n.string("Font Case"),
            accessibilityID: elementID("fontCase"),
            onReset: {
                actions.commit(true) { $0.fontCase = defaults.fontCase }
            }
        ) {
            Menu {
                ForEach(TextStyle.FontCase.allCases, id: \.self) { fontCase in
                    Button(L10n.string(key: fontCase.label)) {
                        actions.commit(true) { $0.fontCase = fontCase }
                    }
                    .accessibilityIdentifier(elementID("fontCase.\(fontCase.rawValue)") ?? "")
                }
            } label: {
                EditorMenuValue(text: selection.value(\.fontCase).map { L10n.string(key: $0.label) } ?? "—")
            }
            .menuStyle(.button)
            .accessibilityElement(children: .combine)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .focusable(false)
            .accessibilityLabel(L10n.string("Font Case"))
            .accessibilityIdentifier(elementID("fontCase") ?? "")
        }
    }

    private var alignmentRow: some View {
        InspectorRow(
            label: L10n.string("Alignment"),
            accessibilityID: elementID("alignment"),
            onReset: {
                actions.commit(false) { $0.alignment = defaults.alignment }
            }
        ) {
            Picker(
                String(),
                selection: Binding(
                    get: { selection.primary.alignment },
                    set: { value in actions.commit(false) { $0.alignment = value } }
                )
            ) {
                Image(systemName: "text.alignleft")
                    .accessibilityLabel(L10n.string("Left"))
                    .accessibilityIdentifier(elementID("alignment.left") ?? "")
                    .tag(TextStyle.Alignment.left)
                Image(systemName: "text.aligncenter")
                    .accessibilityLabel(L10n.string("Center"))
                    .accessibilityIdentifier(elementID("alignment.center") ?? "")
                    .tag(TextStyle.Alignment.center)
                Image(systemName: "text.alignright")
                    .accessibilityLabel(L10n.string("Right"))
                    .accessibilityIdentifier(elementID("alignment.right") ?? "")
                    .tag(TextStyle.Alignment.right)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .tint(AppTheme.Accent.primary.opacity(AppTheme.Opacity.strong))
            .fixedSize()
            .accessibilityLabel(L10n.string("Alignment"))
            .accessibilityIdentifier(elementID("alignment") ?? "")
        }
    }

    private var outlineGroup: some View {
        decorationGroup(
            L10n.string("Outline"),
            accessibilityIDSuffix: "outline",
            isExpanded: $outlineExpanded,
            fitToContent: true,
            enabledKeyPath: \.border.enabled,
            debounceKeys: ["outlineColor"],
            onReset: { $0.border = defaults.border }
        ) {
            colorRow(
                label: L10n.string("Color"),
                debounceKey: "outlineColor",
                accessibilityIDSuffix: "outline.color",
                keyPath: \.border.color
            )
            numberRow(
                label: L10n.string("Width"),
                accessibilityIDSuffix: "outline.width",
                range: 0...40,
                format: "%.1f",
                suffix: " pt",
                fitToContent: true,
                keyPath: \.border.width
            )
        }
    }

    private var shadowGroup: some View {
        decorationGroup(
            L10n.string("Shadow"),
            accessibilityIDSuffix: "shadow",
            isExpanded: $shadowExpanded,
            fitToContent: true,
            enabledKeyPath: \.shadow.enabled,
            debounceKeys: ["shadowColor"],
            onReset: { $0.shadow = defaults.shadow }
        ) {
            colorRow(
                label: L10n.string("Color"),
                debounceKey: "shadowColor",
                accessibilityIDSuffix: "shadow.color",
                preservesOpacity: true,
                keyPath: \.shadow.color
            )
            numberRow(
                label: L10n.string("Opacity"),
                accessibilityIDSuffix: "shadow.opacity",
                range: 0...1,
                displayMultiplier: 100,
                format: "%.0f",
                suffix: "%",
                keyPath: \.shadow.color.a
            )
            pairRow(
                label: L10n.string("Offset"),
                accessibilityIDSuffix: "shadow.offset",
                range: -200...200,
                fitToContent: true,
                xKeyPath: \.shadow.offsetX,
                yKeyPath: \.shadow.offsetY
            )
            numberRow(
                label: L10n.string("Blur"),
                accessibilityIDSuffix: "shadow.blur",
                range: 0...100,
                format: "%.1f",
                suffix: " pt",
                fitToContent: true,
                keyPath: \.shadow.blur
            )
        }
    }

    private var backgroundGroup: some View {
        decorationGroup(
            L10n.string("Background"),
            accessibilityIDSuffix: "background",
            isExpanded: $backgroundExpanded,
            fitToContent: true,
            enabledKeyPath: \.background.enabled,
            debounceKeys: ["backgroundColor", "backgroundOutlineColor"],
            onReset: { $0.background = defaults.background }
        ) {
            colorRow(
                label: L10n.string("Color"),
                debounceKey: "backgroundColor",
                accessibilityIDSuffix: "background.color",
                preservesOpacity: true,
                keyPath: \.background.color
            )
            numberRow(
                label: L10n.string("Opacity"),
                accessibilityIDSuffix: "background.opacity",
                range: 0...1,
                displayMultiplier: 100,
                format: "%.0f",
                suffix: "%",
                keyPath: \.background.color.a
            )
            pairRow(
                label: L10n.string("Padding"),
                accessibilityIDSuffix: "background.padding",
                range: 0...300,
                fitToContent: true,
                xKeyPath: \.background.paddingX,
                yKeyPath: \.background.paddingY
            )
            pairRow(
                label: L10n.string("Center"),
                accessibilityIDSuffix: "background.center",
                range: -500...500,
                xKeyPath: \.background.offsetX,
                yKeyPath: \.background.offsetY
            )
            numberRow(
                label: L10n.string("Corner Radius"),
                accessibilityIDSuffix: "background.cornerRadius",
                range: 0...300,
                format: "%.1f",
                suffix: " pt",
                keyPath: \.background.cornerRadius
            )
            colorRow(
                label: L10n.string("Outline Color"),
                debounceKey: "backgroundOutlineColor",
                accessibilityIDSuffix: "background.outlineColor",
                keyPath: \.background.outlineColor
            )
            numberRow(
                label: L10n.string("Outline Width"),
                accessibilityIDSuffix: "background.outlineWidth",
                range: 0...40,
                format: "%.1f",
                suffix: " pt",
                keyPath: \.background.outlineWidth
            )
        }
    }

    private func decorationGroup<Content: View>(
        _ title: String,
        accessibilityIDSuffix: String,
        isExpanded: Binding<Bool>,
        fitToContent: Bool = false,
        enabledKeyPath: WritableKeyPath<TextStyle, Bool>,
        debounceKeys: [String],
        onReset: @escaping TextStyleEditingActions.Mutation,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        let enabled = selection.value(enabledKeyPath)
        return EditorPanelGroup(
            title,
            accessibilityID: elementID(accessibilityIDSuffix),
            isExpanded: isExpanded,
            onReset: {
                debounceKeys.forEach(actions.cancelPending)
                actions.commit(fitToContent, onReset)
            },
            headerAccessory: {
                Toggle(
                    String(),
                    isOn: Binding(
                        get: { enabled ?? false },
                        set: { value in
                            actions.commit(fitToContent) {
                                $0[keyPath: enabledKeyPath] = value
                            }
                        }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(AppTheme.Text.primaryColor.opacity(AppTheme.Opacity.strong))
                .accessibilityLabel(L10n.string(key: title))
                .accessibilityIdentifier(elementID("\(accessibilityIDSuffix).enabled") ?? "")
            }
        ) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.smMd) {
                content()
            }
            .disabled(enabled != true)
            .opacity(enabled == true ? AppTheme.Opacity.opaque : AppTheme.Opacity.medium)
        }
    }

    private func colorRow(
        label: String,
        debounceKey: String,
        accessibilityIDSuffix: String,
        preservesOpacity: Bool = false,
        keyPath: WritableKeyPath<TextStyle, TextStyle.RGBA>
    ) -> some View {
        InspectorRow(
            label: label,
            accessibilityID: elementID(accessibilityIDSuffix),
            onReset: {
                actions.cancelPending(debounceKey)
                actions.commit(false) {
                    if preservesOpacity {
                        $0[keyPath: keyPath].setRGB(from: defaults[keyPath: keyPath])
                    } else {
                        $0[keyPath: keyPath] = defaults[keyPath: keyPath]
                    }
                }
            }
        ) {
            ColorField(
                displayColor: selection.primary[keyPath: keyPath].swiftUIColor,
                onUserChange: { color in
                    actions.commitColor(debounceKey) {
                        let value = TextStyle.RGBA(color)
                        if preservesOpacity {
                            $0[keyPath: keyPath].setRGB(from: value)
                        } else {
                            $0[keyPath: keyPath] = value
                        }
                    }
                },
                supportsOpacity: !preservesOpacity
            )
            .accessibilityLabel(label)
            .accessibilityIdentifier(elementID(accessibilityIDSuffix) ?? "")
        }
    }

    private var textSizeRow: some View {
        InspectorRow(
            label: L10n.string("Size"),
            accessibilityID: elementID("size"),
            onReset: {
                editor.resetTextSize(
                    clipIds: keyframeClips.map(\.id),
                    defaultSize: defaults.fontSize
                )
            }
        ) {
            InspectorKeyframePropertyControl(
                clips: keyframeClips,
                property: .scale,
                label: L10n.string("Size"),
                accessibilityID: elementID("size") ?? ""
            )
        }
    }

    private func numberRow(
        label: String,
        accessibilityIDSuffix: String,
        range: ClosedRange<Double>,
        displayMultiplier: Double = 1,
        format: String,
        suffix: String,
        fitToContent: Bool = false,
        keyPath: WritableKeyPath<TextStyle, Double>
    ) -> some View {
        InspectorRow(
            label: label,
            accessibilityID: elementID(accessibilityIDSuffix),
            onReset: {
                actions.commit(fitToContent) {
                    $0[keyPath: keyPath] = defaults[keyPath: keyPath]
                }
            }
        ) {
            ScrubbableNumberField(
                value: selection.value(keyPath),
                range: range,
                displayMultiplier: displayMultiplier,
                format: format,
                valueSuffix: suffix,
                fieldWidth: AppTheme.EditorPanel.numericFieldWidth,
                onChanged: { value in
                    actions.apply(fitToContent) { $0[keyPath: keyPath] = value }
                }
            ) { value in
                actions.commit(fitToContent) { $0[keyPath: keyPath] = value }
            }
            .accessibilityLabel(label)
            .accessibilityIdentifier(elementID(accessibilityIDSuffix) ?? "")
        }
    }

    private func pairRow(
        label: String,
        accessibilityIDSuffix: String,
        range: ClosedRange<Double>,
        fitToContent: Bool = false,
        xKeyPath: WritableKeyPath<TextStyle, Double>,
        yKeyPath: WritableKeyPath<TextStyle, Double>
    ) -> some View {
        InspectorRow(
            label: label,
            accessibilityID: elementID(accessibilityIDSuffix),
            onReset: {
                actions.commit(fitToContent) {
                    $0[keyPath: xKeyPath] = defaults[keyPath: xKeyPath]
                    $0[keyPath: yKeyPath] = defaults[keyPath: yKeyPath]
                }
            }
        ) {
            HStack(spacing: AppTheme.Spacing.sm) {
                axisField(
                    value: selection.value(xKeyPath),
                    label: "X",
                    rowLabel: label,
                    accessibilityID: elementID("\(accessibilityIDSuffix).x"),
                    range: range
                ) { value, commit in
                    updateNumber(value, keyPath: xKeyPath, fitToContent: fitToContent, commit: commit)
                }
                axisField(
                    value: selection.value(yKeyPath),
                    label: "Y",
                    rowLabel: label,
                    accessibilityID: elementID("\(accessibilityIDSuffix).y"),
                    range: range
                ) { value, commit in
                    updateNumber(value, keyPath: yKeyPath, fitToContent: fitToContent, commit: commit)
                }
            }
            .fixedSize()
        }
    }

    private func axisField(
        value: Double?,
        label: String,
        rowLabel: String,
        accessibilityID: String?,
        range: ClosedRange<Double>,
        update: @escaping (_ value: Double, _ commit: Bool) -> Void
    ) -> some View {
        ScrubbableNumberField(
            value: value,
            range: range,
            format: "%.1f",
            fieldWidth: AppTheme.EditorPanel.compactNumericFieldWidth,
            trailingLabel: label,
            onChanged: { update($0, false) }
        ) { update($0, true) }
        .accessibilityLabel(Text(verbatim: "\(rowLabel) \(label)"))
        .accessibilityIdentifier(accessibilityID ?? "")
    }

    private func elementID(_ suffix: String) -> String? {
        accessibilityID.map { "\($0).\(suffix)" }
    }

    private func updateNumber(
        _ value: Double,
        keyPath: WritableKeyPath<TextStyle, Double>,
        fitToContent: Bool,
        commit: Bool
    ) {
        let mutation: TextStyleEditingActions.Mutation = { $0[keyPath: keyPath] = value }
        if commit {
            actions.commit(fitToContent, mutation)
        } else {
            actions.apply(fitToContent, mutation)
        }
    }
}

extension TextStyleControls where AfterAlignment == EmptyView, AfterColor == EmptyView {
    init(
        selection: TextStyleSelection,
        defaults: TextStyle,
        styleExpanded: Binding<Bool>? = nil,
        groupsExpandedByDefault: Bool = true,
        actions: TextStyleEditingActions
    ) {
        self.init(
            selection: selection,
            defaults: defaults,
            styleExpanded: styleExpanded,
            groupsExpandedByDefault: groupsExpandedByDefault,
            actions: actions,
            afterAlignment: { EmptyView() },
            afterColor: { EmptyView() }
        )
    }
}
