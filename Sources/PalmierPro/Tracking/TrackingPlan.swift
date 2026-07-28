import Foundation

/// Which frames to analyse, and which of the subject's source frames they show.
///
/// The two clips have their own placement, trim and speed, and only their overlap
/// can be tracked: outside it one of them is not on screen, so there is nothing to
/// measure or nothing to mask.
struct TrackingPlan: Sendable, Equatable {
    let overlap: ClosedRange<Int>
    /// Project-timeline frames, in order.
    let timelineFrames: [Int]
    /// The subject's own source frame for each entry above.
    let sourceFrames: [Int]

    init?(target: Clip, subject: Clip, window: ClosedRange<Int>, step: Int) {
        let low = max(window.lowerBound, max(target.startFrame, subject.startFrame))
        let high = min(window.upperBound, min(target.endFrame, subject.endFrame) - 1)
        guard low <= high else { return nil }
        overlap = low...high
        timelineFrames = stride(from: low, through: high, by: max(1, step)).map { $0 }
        // Trim and speed are the SUBJECT's: they decide which of its frames is on screen.
        sourceFrames = timelineFrames.map {
            subject.trimStartFrame + Int((Double($0 - subject.startFrame) * subject.speed).rounded())
        }
    }
}
