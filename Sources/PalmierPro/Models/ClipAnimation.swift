import Foundation

/// A preset move over a clip's opening (entrance) or closing (exit) frames.
struct ClipAnimation: Codable, Sendable, Equatable {
    enum Preset: String, Codable, CaseIterable, Sendable {
        case slideLeft, slideRight, slideUp, slideDown, zoomIn, zoomOut

        var displayName: String {
            switch self {
            case .slideLeft: L10n.key("Slide Left")
            case .slideRight: L10n.key("Slide Right")
            case .slideUp: L10n.key("Slide Up")
            case .slideDown: L10n.key("Slide Down")
            case .zoomIn: L10n.key("Zoom In")
            case .zoomOut: L10n.key("Zoom Out")
            }
        }
    }

    var preset: Preset
    var durationFrames: Int
}

/// Pure per-frame evaluator for clip entrance and exit animations.
enum ClipAnimator {
    struct Motion: Equatable {
        var dx: Double = 0
        var dy: Double = 0
        var scale: Double = 1
        var opacity: Double = 1
        static let identity = Motion()
    }

    /// Scale change a zoom preset travels between its rest and far end.
    static let zoomAmount = 0.5

    /// `box` is the clip's resolved transform at the frame, in normalized canvas space.
    static func motion(for clip: Clip, atOffset offset: Int, box: Transform) -> Motion {
        guard offset >= 0, offset < clip.durationFrames else { return .identity }
        if let entrance = clip.inAnimation, entrance.durationFrames > 0, offset < entrance.durationFrames {
            let remaining = 1 - easeOutCubic(Double(offset) / Double(entrance.durationFrames))
            return displacement(entrance.preset, amount: remaining, box: box, entering: true)
        }
        if let exit = clip.outAnimation, exit.durationFrames > 0 {
            let exitStart = clip.durationFrames - exit.durationFrames
            guard offset >= exitStart else { return .identity }
            let progress = easeInCubic(Double(offset - exitStart + 1) / Double(exit.durationFrames))
            return displacement(exit.preset, amount: progress, box: box, entering: false)
        }
        return .identity
    }

    /// `amount` is 0 at rest and 1 at the far end (fully off canvas or fully faded).
    private static func displacement(
        _ preset: ClipAnimation.Preset,
        amount: Double,
        box: Transform,
        entering: Bool
    ) -> Motion {
        let left = box.centerX - box.width / 2
        let top = box.centerY - box.height / 2
        let toLeftEdge = max(0, left + box.width)
        let toRightEdge = max(0, 1 - left)
        let toTopEdge = max(0, top + box.height)
        let toBottomEdge = max(0, 1 - top)
        // An entrance travels in the named direction, so it starts on the opposite side.
        switch preset {
        case .slideLeft:
            return Motion(dx: entering ? toRightEdge * amount : -toLeftEdge * amount)
        case .slideRight:
            return Motion(dx: entering ? -toLeftEdge * amount : toRightEdge * amount)
        case .slideUp:
            return Motion(dy: entering ? toBottomEdge * amount : -toTopEdge * amount)
        case .slideDown:
            return Motion(dy: entering ? -toTopEdge * amount : toBottomEdge * amount)
        case .zoomIn:
            return Motion(scale: 1 + (entering ? -1 : 1) * zoomAmount * amount, opacity: 1 - amount)
        case .zoomOut:
            return Motion(scale: 1 + (entering ? 1 : -1) * zoomAmount * amount, opacity: 1 - amount)
        }
    }

    private static func easeOutCubic(_ t: Double) -> Double {
        let u = 1 - min(1, max(0, t))
        return 1 - u * u * u
    }

    private static func easeInCubic(_ t: Double) -> Double {
        let c = min(1, max(0, t))
        return c * c * c
    }
}

extension Clip {
    var supportsClipAnimation: Bool {
        switch mediaType {
        case .video, .image, .lottie, .sequence: true
        case .audio, .text, .subtitle: false
        }
    }

    /// Where the renderer places the clip: the authored transform plus any entrance or exit move.
    func presentedTransformAt(frame: Int) -> Transform {
        var t = transformAt(frame: frame)
        guard inAnimation != nil || outAnimation != nil else { return t }
        let motion = ClipAnimator.motion(for: self, atOffset: frame - startFrame, box: t)
        t.centerX += motion.dx
        t.centerY += motion.dy
        t.width *= motion.scale
        t.height *= motion.scale
        return t
    }

    func animationOpacityMultiplier(at frame: Int) -> Double {
        guard inAnimation != nil || outAnimation != nil else { return 1 }
        return ClipAnimator.motion(for: self, atOffset: frame - startFrame, box: transform).opacity
    }

    /// The clip now opens mid-content, so opening ramps would replay from the cut.
    mutating func clearHeadRamps() {
        fadeInFrames = 0
        inAnimation = nil
        if textAnimation?.preset.isEntrance == true { textAnimation = nil }
    }

    /// The clip now ends mid-content, so closing ramps would play early.
    mutating func clearTailRamps() {
        fadeOutFrames = 0
        outAnimation = nil
    }

    /// Longest animation that fits beside the opposite edge's animation.
    func maxAnimationFrames(_ edge: FadeEdge) -> Int {
        let other = edge == .left ? outAnimation : inAnimation
        return max(0, durationFrames - (other?.durationFrames ?? 0))
    }

    /// Retimes both animations for a frame-rate change; callers clamp afterwards.
    mutating func rescaleAnimations(by scale: Double) {
        for keyPath in [\Clip.inAnimation, \Clip.outAnimation] {
            guard var animation = self[keyPath: keyPath] else { continue }
            animation.durationFrames = max(1, Int((Double(animation.durationFrames) * scale).rounded()))
            self[keyPath: keyPath] = animation
        }
    }

    /// Entrance keeps priority; animations that no longer fit are shortened, and dropped at zero.
    mutating func clampAnimationsToDuration() {
        if var entrance = inAnimation {
            entrance.durationFrames = min(entrance.durationFrames, durationFrames)
            inAnimation = entrance.durationFrames > 0 ? entrance : nil
        }
        if var exit = outAnimation {
            exit.durationFrames = min(exit.durationFrames, maxAnimationFrames(.right))
            outAnimation = exit.durationFrames > 0 ? exit : nil
        }
    }
}
