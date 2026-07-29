import AVFoundation
import CoreGraphics
import Foundation
import Vision

/// Per-frame subject positions from Vision, for driving a clip's path mask.
///
/// Two modes, because they fail differently. Hand landmarks are DETECTED fresh on
/// every frame — no history, so no drift, and every frame carries its own
/// confidence. Region tracking follows one box forward from a seed, which is the
/// only option for a subject Vision has no detector for, but its error accumulates:
/// measured against hand landmarks on a 61-frame clip it stayed under 0.02 for the
/// first ten frames and reached 0.22 by the end. That is why `region` reports
/// confidence per frame and callers are expected to stop at the first collapse
/// rather than write the rest of the track.
enum SubjectTracker {

    struct Sample: Sendable {
        let frame: Int
        /// Normalized, top-left origin — the mask's coordinate space.
        let points: [CGPoint]
        let confidence: Double
        /// Distance between the two hands' index tips, in `hands` mode. Near zero when
        /// the fingertips touch, which is how a deliberate "pinch" reads in the data.
        let span: Double?

        init(frame: Int, points: [CGPoint], confidence: Double, span: Double? = nil) {
            self.frame = frame
            self.points = points
            self.confidence = confidence
            self.span = span
        }
    }

    enum Failure: LocalizedError {
        case noVideoTrack
        case handsNotFound(frame: Int)
        case seedOutsideFrame

        var errorDescription: String? {
            switch self {
            case .noVideoTrack: "The asset has no video track to track."
            case .handsNotFound(let f): "No pair of hands found at frame \(f)."
            case .seedOutsideFrame: "The seed region lies outside the frame."
            }
        }
    }

    /// A quad spanning both hands: left thumb tip, right index tip, right thumb tip,
    /// left index tip — the corners the "framing" gesture actually makes.
    @concurrent
    static func hands(
        url: URL,
        sourceFrames: [Int],
        fps: Double,
        minimumConfidence: Double
    ) async throws -> [Sample] {
        let generator = try await imageGenerator(url: url)
        var out: [Sample] = []
        for source in sourceFrames {
            try Task.checkCancellation()
            guard let image = try? await cgImage(generator, sourceFrame: source, fps: fps) else { continue }
            let request = VNDetectHumanHandPoseRequest()
            request.maximumHandCount = 2
            try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            guard let quad = quad(from: request.results ?? [], minimumConfidence: minimumConfidence) else { continue }
            out.append(Sample(frame: source, points: quad.points, confidence: quad.confidence, span: quad.span))
        }
        return out
    }

    /// Follows one region forward from `seed`, reporting the centre and the box's
    /// scale change so a caller can move a mask rigidly.
    @concurrent
    static func region(
        url: URL,
        seed: CGRect,
        sourceFrames: [Int],
        fps: Double
    ) async throws -> [Sample] {
        guard seed.width > 0, seed.height > 0,
              seed.minX >= -0.5, seed.maxX <= 1.5, seed.minY >= -0.5, seed.maxY <= 1.5
        else { throw Failure.seedOutsideFrame }
        let generator = try await imageGenerator(url: url)
        // Vision boxes are bottom-left origin; the seed arrives top-left.
        var observation = VNDetectedObjectObservation(boundingBox: CGRect(
            x: seed.minX, y: 1 - seed.maxY, width: seed.width, height: seed.height))
        let handler = VNSequenceRequestHandler()
        var out: [Sample] = []
        for source in sourceFrames {
            try Task.checkCancellation()
            guard let image = try? await cgImage(generator, sourceFrame: source, fps: fps) else { continue }
            let request = VNTrackObjectRequest(detectedObjectObservation: observation)
            request.trackingLevel = .accurate
            try? handler.perform([request], on: image)
            guard let result = request.results?.first as? VNDetectedObjectObservation else { break }
            observation = result
            let b = result.boundingBox
            let scale = seed.width > 0 ? Double(b.width) / Double(seed.width) : 1
            out.append(Sample(
                frame: source,
                points: [CGPoint(x: b.midX, y: 1 - b.midY), CGPoint(x: scale, y: scale)],
                confidence: Double(result.confidence)
            ))
        }
        return out
    }

    // MARK: - Vision plumbing

    /// Confidence is the minimum over the FOUR joints actually used, not over all 21:
    /// a curled little finger says nothing about whether the corners are trustworthy,
    /// and folding it in throws away most of a usable clip.
    private static func quad(
        from observations: [VNHumanHandPoseObservation],
        minimumConfidence: Double
    ) -> (points: [CGPoint], confidence: Double, span: Double)? {
        guard observations.count >= 2 else { return nil }
        struct Tips { let thumb: CGPoint; let index: CGPoint; let confidence: Double }
        let tips: [Tips] = observations.compactMap { obs in
            guard let thumb = try? obs.recognizedPoint(.thumbTip),
                  let index = try? obs.recognizedPoint(.indexTip) else { return nil }
            // Vision's y grows upward; the mask's grows downward.
            return Tips(
                thumb: CGPoint(x: thumb.location.x, y: 1 - thumb.location.y),
                index: CGPoint(x: index.location.x, y: 1 - index.location.y),
                confidence: Double(min(thumb.confidence, index.confidence))
            )
        }
        guard tips.count >= 2 else { return nil }
        // Left/right by where the hand sits in frame, not by Vision's chirality:
        // a mirrored front camera reports the opposite of what the editor shows.
        let ordered = tips.sorted { min($0.thumb.x, $0.index.x) < min($1.thumb.x, $1.index.x) }
        let left = ordered[0], right = ordered[1]
        let confidence = min(left.confidence, right.confidence)
        guard confidence >= minimumConfidence else { return nil }
        let span = hypot(left.index.x - right.index.x, left.index.y - right.index.y)
        return ([left.thumb, right.index, right.thumb, left.index], confidence, Double(span))
    }

    private static func imageGenerator(url: URL) async throws -> AVAssetImageGenerator {
        let asset = AVURLAsset(url: url)
        guard try await !asset.loadTracks(withMediaType: .video).isEmpty else {
            throw Failure.noVideoTrack
        }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return generator
    }

    private static func cgImage(
        _ generator: AVAssetImageGenerator,
        sourceFrame: Int,
        fps: Double
    ) async throws -> CGImage {
        let scale = CMTimeScale(max(1, fps.rounded()))
        let time = CMTime(value: CMTimeValue(sourceFrame), timescale: scale)
        return try await generator.image(at: time).image
    }
}
