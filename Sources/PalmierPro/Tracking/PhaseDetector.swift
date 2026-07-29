import Foundation

/// Finds the moments a gesture resets, so a mask can change shape there without the
/// editor hand-picking frames.
///
/// The signal is the distance between the two hands' index tips. Bringing the
/// fingertips together is a deliberate, full-amplitude move — on a test clip it ran
/// from 0.004 to 0.548, a range of two orders of magnitude — which makes it far more
/// robust than reading a pose signature off all 21 landmarks, where any one passive
/// joint twitching registers as change.
enum PhaseDetector {

    struct Boundary: Sendable, Equatable {
        /// Frame of the closest approach.
        let frame: Int
        let span: Double
    }

    /// The span below which the hands count as touching.
    ///
    /// Shared with the mask builder on purpose: the interval that marks a phase
    /// boundary is exactly the interval where the four corners have collapsed onto
    /// each other and no shape drawn from them means anything. One threshold, so the
    /// two can never disagree about where a phase starts.
    static func closedThreshold(spans: [Double], closedFraction: Double = 0.25) -> Double? {
        guard spans.count >= 3, let lo = spans.min(), let hi = spans.max() else { return nil }
        let range = hi - lo
        guard range > 0.05 else { return nil }
        return lo + range * closedFraction
    }

    /// Frames where the hands came together. `spans` must be in frame order.
    ///
    /// `closedFraction` is where "touching" starts, as a fraction of the observed range;
    /// `openFraction` is how far apart the hands must travel before another approach
    /// counts as a new one, which stops a single wobbly pinch reading as several.
    static func boundaries(
        spans: [(frame: Int, span: Double)],
        closedFraction: Double = 0.25,
        openFraction: Double = 0.5
    ) -> [Boundary] {
        let values = spans.map(\.span)
        // A hand pair that never really closes has no phases to find; without this a
        // clip of steady framing would report noise as boundaries.
        guard let closed = closedThreshold(spans: values, closedFraction: closedFraction),
              let lo = values.min(), let hi = values.max() else { return [] }
        let open = lo + (hi - lo) * openFraction

        var out: [Boundary] = []
        var run: [(frame: Int, span: Double)] = []
        var openedSince = true

        for entry in spans {
            if entry.span <= closed {
                if openedSince { run.append(entry) }
            } else {
                if !run.isEmpty, let best = run.min(by: { $0.span < $1.span }) {
                    out.append(Boundary(frame: best.frame, span: best.span))
                    run = []
                    openedSince = false
                }
                if entry.span >= open { openedSince = true }
            }
        }
        if !run.isEmpty, let best = run.min(by: { $0.span < $1.span }) {
            out.append(Boundary(frame: best.frame, span: best.span))
        }
        return out
    }
}
