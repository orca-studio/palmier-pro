import Foundation

struct WordTiming: Codable, Sendable, Equatable, Hashable {
    var text: String
    var startFrame: Int
    var endFrame: Int
}

struct TextAnimation: Codable, Sendable, Equatable {
    var preset: Preset = .none
    var durationFrames: Int = TextAnimation.defaultDurationFrames
    var highlight: TextStyle.RGBA?

    enum Preset: String, Codable, CaseIterable, Sendable {
        case none
        // Whole-clip / per-line.
        case popIn, slideUp, typewriter
        // Per word.
        case wordReveal, wordSlide, highlightPop, highlightBlock

        enum RenderMode { case entrance, perWord, typewriter }

        var renderMode: RenderMode {
            switch self {
            case .none, .popIn, .slideUp: .entrance
            case .typewriter: .typewriter
            case .wordReveal, .wordSlide, .highlightPop, .highlightBlock: .perWord
            }
        }

        var isPerWord: Bool { renderMode == .perWord }
        var isEntrance: Bool { self == .popIn || self == .slideUp }
        var usesHighlight: Bool { isPerWord }

        var displayName: String {
            switch self {
            case .none: L10n.key("Off")
            case .popIn: L10n.key("Pop In")
            case .slideUp: L10n.key("Slide Up")
            case .typewriter: L10n.key("Typewriter")
            case .wordReveal: L10n.key("Word Reveal")
            case .wordSlide: L10n.key("Word Slide")
            case .highlightPop: L10n.key("Highlight")
            case .highlightBlock: L10n.key("Highlight Block")
            }
        }

        static let agentValues: [String] = ["off"] + allCases.filter { $0 != .none }.map(\.rawValue)

        static let perLine: [Preset] = [.popIn, .slideUp, .typewriter]
        static let perWord: [Preset] = [.wordReveal, .wordSlide, .highlightPop, .highlightBlock]
    }

    var isActive: Bool { preset != .none }

    static let defaultDurationFrames = 6
    static let defaultHighlight = TextStyle.RGBA(r: 1, g: 0.85, b: 0, a: 1)

    private enum CodingKeys: String, CodingKey { case preset, durationFrames, highlight }

    init(preset: Preset = .none, durationFrames: Int = TextAnimation.defaultDurationFrames, highlight: TextStyle.RGBA? = nil) {
        self.preset = preset
        self.durationFrames = durationFrames
        self.highlight = highlight
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            preset: (try? c.decode(Preset.self, forKey: .preset)) ?? .none,
            durationFrames: (try? c.decode(Int.self, forKey: .durationFrames)) ?? TextAnimation.defaultDurationFrames,
            highlight: try? c.decode(TextStyle.RGBA.self, forKey: .highlight)
        )
    }
}
