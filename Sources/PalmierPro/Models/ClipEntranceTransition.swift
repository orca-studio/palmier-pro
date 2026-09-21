import Foundation

/// A transition from the lower composite into this clip during its opening frames.
struct ClipEntranceTransition: Codable, Sendable, Equatable {
    enum Style: String, Codable, Sendable { case slideBlackBand }
    let style: Style
    let durationFrames: Int

    func progress(atOffset offset: Int) -> Double? {
        guard durationFrames > 0, offset >= 0, offset < durationFrames else { return nil }
        return Double(offset) / Double(durationFrames)
    }
}
