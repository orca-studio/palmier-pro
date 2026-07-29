import CoreGraphics
import Foundation

// Turns tracked subject positions into a clip's mask keyframes.
extension EditorViewModel {

    struct TrackingResult: Sendable {
        let keyframesWritten: Int
        let trackedRange: ClosedRange<Int>?
        /// Where confidence collapsed, if it did. Frames past this are NOT written:
        /// a mask that quietly slides off the subject is worse than one that stops.
        let lostAtFrame: Int?
        let skippedFrames: [Int]
        /// Frames where the hands came together, i.e. where the shape may change.
        let phaseBoundaries: [Int]
    }

    enum TrackingMode: String, Sendable {
        case hands
        case region
    }

    /// Track a subject and write the result as `clipId`'s mask keyframes.
    ///
    /// `sourceClipId` is where the subject lives; it defaults to the masked clip but
    /// is usually a DIFFERENT one — masking a clip so it shows only inside a shape
    /// held by hands in the footage below means analysing the lower clip and masking
    /// the upper one.
    ///
    /// `region` needs a mask already on the target: it follows that shape's bounding
    /// box and moves the whole path rigidly. `hands` builds its own quad.
    func trackSubject(
        clipId: String,
        mode: TrackingMode,
        sourceClipId: String? = nil,
        range: ClosedRange<Int>? = nil,
        minimumConfidence: Double = 0.3,
        step: Int = 1,
        phaseShapes: [[Int]]? = nil,
        hideWhenClosed: Bool = true
    ) async throws -> TrackingResult {
        guard let clip = clipFor(id: clipId) else {
            throw TrackingError.clipNotFound(clipId)
        }
        let subject = try subjectClip(sourceClipId, fallback: clip)
        guard let asset = mediaAssets.first(where: { $0.id == subject.mediaRef }) else {
            throw TrackingError.mediaMissing
        }
        let fps = Double(timeline.fps)
        let window = (range ?? clip.startFrame...(clip.endFrame - 1))
            .clamped(to: clip.startFrame...(clip.endFrame - 1))
        guard window.lowerBound <= window.upperBound else {
            throw TrackingError.emptyRange
        }
        guard let plan = TrackingPlan(target: clip, subject: subject, window: window, step: step) else {
            throw TrackingError.noOverlap(subject.id)
        }
        let overlap = plan.overlap
        let timelineFrames = plan.timelineFrames
        let sourceFrames = plan.sourceFrames

        let samples: [SubjectTracker.Sample]
        switch mode {
        case .hands:
            samples = try await SubjectTracker.hands(
                url: asset.url, sourceFrames: sourceFrames, fps: fps,
                minimumConfidence: minimumConfidence
            )
        case .region:
            guard let shape = clip.maskAt(frame: overlap.lowerBound), shape.isRenderable else {
                throw TrackingError.regionNeedsMask
            }
            samples = try await SubjectTracker.region(
                url: asset.url, seed: Self.boundingBox(of: shape), sourceFrames: sourceFrames, fps: fps
            )
        }

        // Boundaries are read off the same samples the mask is built from, so a frame
        // that was too weak to mask is also too weak to split a phase on.
        let bySourceFrame = Dictionary(uniqueKeysWithValues: zip(plan.sourceFrames, plan.timelineFrames))
        let spans: [(frame: Int, span: Double)] = samples.compactMap { sample in
            guard sample.confidence >= minimumConfidence,
                  let span = sample.span,
                  let timelineFrame = bySourceFrame[sample.frame] else { return nil }
            return (timelineFrame, span)
        }
        let boundaries = PhaseDetector.boundaries(spans: spans).map(\.frame)
        let closedSpan = hideWhenClosed ? PhaseDetector.closedThreshold(spans: spans.map(\.span)) : nil

        let base = clip.maskAt(frame: overlap.lowerBound)
        let assembled = Self.assemble(
            samples: samples, plan: plan, mode: mode, base: base,
            clipStartFrame: clip.startFrame, minimumConfidence: minimumConfidence,
            phaseShapes: phaseShapes, boundaries: boundaries, closedSpan: closedSpan
        )
        let lost = assembled.lostAtFrame
        let skipped = assembled.skippedFrames
        guard !assembled.track.keyframes.isEmpty else {
            throw TrackingError.nothingTracked(mode: mode)
        }
        let track = assembled.track
        commitClipProperty(clipId: clipId, actionName: "Track Subject") { clip in
            clip.maskTrack = track
            if clip.mask == nil { clip.mask = track.keyframes[0].value }
        }
        return TrackingResult(
            keyframesWritten: track.keyframes.count,
            trackedRange: (track.keyframes.first!.frame + clip.startFrame)...(track.keyframes.last!.frame + clip.startFrame),
            lostAtFrame: lost,
            skippedFrames: skipped.sorted(),
            phaseBoundaries: boundaries
        )
    }

    /// Samples → keyframes. Pure, so the confidence and skip rules can be tested
    /// without driving Vision over a real file.
    static func assemble(
        samples: [SubjectTracker.Sample],
        plan: TrackingPlan,
        mode: TrackingMode,
        base: MaskShape?,
        clipStartFrame: Int,
        minimumConfidence: Double,
        phaseShapes: [[Int]]? = nil,
        boundaries: [Int] = [],
        closedSpan: Double? = nil
    ) -> (track: KeyframeTrack<MaskShape>, lostAtFrame: Int?, skippedFrames: [Int]) {
        let bySource = Dictionary(uniqueKeysWithValues: zip(plan.sourceFrames, plan.timelineFrames))
        var keyframes: [Keyframe<MaskShape>] = []
        var skipped: [Int] = []
        var lost: Int?

        for sample in samples {
            guard let timelineFrame = bySource[sample.frame] else { continue }
            if sample.confidence < minimumConfidence {
                // Stop rather than extrapolate: past this point the tracker no longer
                // knows where the subject is, and later samples are worse, not better.
                lost = timelineFrame
                break
            }
            guard var shape = shape(for: sample, mode: mode, base: base) else {
                skipped.append(timelineFrame)
                continue
            }
            // A phase's shape is an ORDER over the tracked points, not fixed
            // coordinates — so the shape keeps following the hands, and the vertex
            // count cannot change between phases by construction.
            if let phaseShapes, !phaseShapes.isEmpty {
                let phase = boundaries.filter { $0 <= timelineFrame }.count
                let order = phaseShapes[phase % phaseShapes.count]
                if order.allSatisfy({ $0 >= 0 && $0 < shape.vertices.count }), order.count == shape.vertices.count {
                    shape.vertices = order.map { shape.vertices[$0] }
                }
            }
            // Fingertips touching: the four corners have collapsed onto each other and
            // any quad drawn through them is noise — a visible spike, as in the pinch
            // frames. Collapse the path to its centre instead: zero area draws nothing,
            // the vertex count is untouched, and the frames either side interpolate into
            // it, so the shape closes and reopens with the hands for free.
            if let closedSpan, let span = sample.span, span < closedSpan {
                let cx = shape.vertices.reduce(0.0) { $0 + $1.x } / Double(shape.vertices.count)
                let cy = shape.vertices.reduce(0.0) { $0 + $1.y } / Double(shape.vertices.count)
                shape.vertices = shape.vertices.map {
                    MaskVertex(x: cx, y: cy, inControl: $0.inControl, outControl: $0.outControl)
                }
            }
            keyframes.append(Keyframe(
                frame: timelineFrame - clipStartFrame, value: shape, interpolationOut: .linear
            ))
        }
        for frame in plan.timelineFrames where !samples.contains(where: { bySource[$0.frame] == frame }) {
            if let lost, frame >= lost { continue }
            skipped.append(frame)
        }
        return (KeyframeTrack(keyframes: keyframes.sorted { $0.frame < $1.frame }), lost, skipped.sorted())
    }

    static func shape(for sample: SubjectTracker.Sample, mode: TrackingMode, base: MaskShape?) -> MaskShape? {
        switch mode {
        case .hands:
            guard sample.points.count == 4 else { return nil }
            var shape = base ?? MaskShape()
            shape.vertices = canonical(sample.points).map { MaskVertex(x: Double($0.x), y: Double($0.y)) }
            return shape
        case .region:
            // Rigid move: the drawn path keeps its shape and rides the box.
            guard var shape = base, shape.isRenderable, sample.points.count == 2 else { return nil }
            let box = Self.boundingBox(of: shape)
            let origin = CGPoint(x: box.midX, y: box.midY)
            let target = sample.points[0]
            let scale = max(0.05, Double(sample.points[1].x))
            shape.vertices = shape.vertices.map { v in
                MaskVertex(
                    x: Double(target.x) + (v.x - Double(origin.x)) * scale,
                    y: Double(target.y) + (v.y - Double(origin.y)) * scale,
                    inControl: v.inControl, outControl: v.outControl
                )
            }
            return shape
        }
    }

    private func subjectClip(_ id: String?, fallback: Clip) throws -> Clip {
        guard let id, id != fallback.id else { return fallback }
        guard let clip = clipFor(id: id) else { throw TrackingError.clipNotFound(id) }
        return clip
    }

    /// The tracked points arrive in a SEMANTIC order — left thumb, right index, right
    /// thumb, left index — which says nothing about how they sit on screen. As the hands
    /// turn, that same order flips between a simple quad and a crossed one on its own,
    /// so a phase's shape was not actually stable. Sorting by angle about the centroid
    /// makes the base order always trace a simple polygon; a phase permutation on top of
    /// that then means the same thing on every frame.
    static func canonical(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count > 2 else { return points }
        let cx = points.reduce(0) { $0 + $1.x } / CGFloat(points.count)
        let cy = points.reduce(0) { $0 + $1.y } / CGFloat(points.count)
        return points.sorted { atan2($0.y - cy, $0.x - cx) < atan2($1.y - cy, $1.x - cx) }
    }

    static func boundingBox(of shape: MaskShape) -> CGRect {
        let xs = shape.vertices.map(\.x), ys = shape.vertices.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else {
            return .zero
        }
        return CGRect(x: minX, y: minY, width: max(0.001, maxX - minX), height: max(0.001, maxY - minY))
    }

    enum TrackingError: LocalizedError {
        case clipNotFound(String)
        case mediaMissing
        case emptyRange
        case regionNeedsMask
        case noOverlap(String)
        case nothingTracked(mode: TrackingMode)

        var errorDescription: String? {
            switch self {
            case .clipNotFound(let id): "Clip not found: \(id)"
            case .mediaMissing: "The clip's media asset is no longer in the library."
            case .emptyRange: "The requested range does not overlap the clip."
            case .regionNeedsMask: "Region tracking follows an existing mask — draw one first, or use mode 'hands'."
            case .noOverlap(let id): "The masked clip and the subject clip (\(id)) do not overlap in time."
            case .nothingTracked(let mode):
                mode == .hands
                    ? "No frame in the range showed a confident pair of hands."
                    : "The region could not be followed from the first frame."
            }
        }
    }
}

// MARK: - UI entry point

extension EditorViewModel {
    /// Runs a track for the Inspector and surfaces the outcome, including the
    /// partial-success case where tracking stopped early.
    func runSubjectTracking(
        clipId: String, mode: TrackingMode, sourceClipId: String? = nil, phaseShapes: [[Int]]? = nil
    ) async {
        guard trackingClipId == nil else { return }
        trackingClipId = clipId
        trackingNotice = nil
        defer { trackingClipId = nil }
        do {
            let result = try await trackSubject(
                clipId: clipId, mode: mode, sourceClipId: sourceClipId, phaseShapes: phaseShapes
            )
            let phases = result.phaseBoundaries.isEmpty ? "" : " · \(result.phaseBoundaries.count + 1) phases"
            if let lost = result.lostAtFrame {
                trackingNotice = "lost at f\(lost) · \(result.keyframesWritten) kf\(phases)"
            } else {
                trackingNotice = "\(result.keyframesWritten) kf tracked\(phases)"
            }
        } catch {
            trackingNotice = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
