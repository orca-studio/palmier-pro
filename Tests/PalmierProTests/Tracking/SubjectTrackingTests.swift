import CoreGraphics
import Foundation
import Testing
@testable import PalmierPro

@Suite("Tracking plan")
struct TrackingPlanTests {

    private func clip(start: Int, duration: Int, trim: Int = 0, speed: Double = 1) -> Clip {
        var c = Clip(mediaRef: "m", startFrame: start, durationFrames: duration)
        c.trimStartFrame = trim
        c.speed = speed
        return c
    }

    @Test func mapsTimelineFramesThroughTheSubjectsTrim() {
        let target = clip(start: 0, duration: 10)
        let subject = clip(start: 0, duration: 10, trim: 40)
        let plan = TrackingPlan(target: target, subject: subject, window: 0...9, step: 1)
        #expect(plan?.timelineFrames == Array(0...9))
        #expect(plan?.sourceFrames == Array(40...49), "the subject's trim offsets every source frame")
    }

    @Test func speedScalesWhichSourceFrameIsOnScreen() {
        let target = clip(start: 0, duration: 6)
        let subject = clip(start: 0, duration: 6, speed: 2)
        let plan = TrackingPlan(target: target, subject: subject, window: 0...5, step: 1)
        #expect(plan?.sourceFrames == [0, 2, 4, 6, 8, 10])
    }

    /// The subject's placement, not the target's, decides the source frame — the two
    /// clips can start at different points on the timeline.
    @Test func usesTheSubjectsOwnPlacement() {
        let target = clip(start: 100, duration: 10)
        let subject = clip(start: 96, duration: 20, trim: 5)
        let plan = TrackingPlan(target: target, subject: subject, window: 100...109, step: 1)
        #expect(plan?.timelineFrames.first == 100)
        #expect(plan?.sourceFrames.first == 9, "100 is the subject's 4th frame, plus its trim of 5")
    }

    @Test func onlyTheOverlapIsTracked() {
        let target = clip(start: 0, duration: 30)
        let subject = clip(start: 20, duration: 30)
        let plan = TrackingPlan(target: target, subject: subject, window: 0...29, step: 1)
        #expect(plan?.overlap == 20...29)
        #expect(plan?.timelineFrames.first == 20)
        #expect(plan?.timelineFrames.last == 29)
    }

    @Test func disjointClipsHaveNoPlan() {
        let target = clip(start: 0, duration: 10)
        let subject = clip(start: 50, duration: 10)
        #expect(TrackingPlan(target: target, subject: subject, window: 0...9, step: 1) == nil)
    }

    @Test func stepSamplesEveryNthFrame() {
        let c = clip(start: 0, duration: 20)
        let plan = TrackingPlan(target: c, subject: c, window: 0...19, step: 5)
        #expect(plan?.timelineFrames == [0, 5, 10, 15])
    }

    @Test func windowIsClampedToBothClips() {
        let target = clip(start: 10, duration: 10)   // 10..<20
        let subject = clip(start: 0, duration: 100)
        let plan = TrackingPlan(target: target, subject: subject, window: 0...999, step: 1)
        #expect(plan?.overlap == 10...19, "a window wider than the clips is trimmed to them")
    }
}

@Suite("Tracking sample assembly")
@MainActor
struct TrackingAssemblyTests {

    private let quad = [
        CGPoint(x: 0.2, y: 0.2), CGPoint(x: 0.8, y: 0.2),
        CGPoint(x: 0.8, y: 0.8), CGPoint(x: 0.2, y: 0.8),
    ]

    private func plan(frames: Int = 5) -> TrackingPlan {
        let c = Clip(mediaRef: "m", startFrame: 0, durationFrames: frames)
        return TrackingPlan(target: c, subject: c, window: 0...(frames - 1), step: 1)!
    }

    private func sample(_ frame: Int, confidence: Double) -> SubjectTracker.Sample {
        SubjectTracker.Sample(frame: frame, points: quad, confidence: confidence)
    }

    @Test func writesOneKeyframePerConfidentSample() {
        let result = EditorViewModel.assemble(
            samples: (0..<5).map { sample($0, confidence: 0.9) },
            plan: plan(), mode: .hands, base: nil, clipStartFrame: 0, minimumConfidence: 0.3
        )
        #expect(result.track.keyframes.count == 5)
        #expect(result.lostAtFrame == nil)
        #expect(result.skippedFrames.isEmpty)
    }

    /// The contract that matters: a mask that quietly slides off the subject is worse
    /// than one that stops, so nothing after the collapse is written.
    @Test func stopsAtTheFirstLowConfidenceSampleAndWritesNothingAfter() {
        var samples = (0..<5).map { sample($0, confidence: 0.9) }
        samples[2] = sample(2, confidence: 0.1)
        let result = EditorViewModel.assemble(
            samples: samples, plan: plan(), mode: .hands, base: nil,
            clipStartFrame: 0, minimumConfidence: 0.3
        )
        #expect(result.track.keyframes.map(\.frame) == [0, 1])
        #expect(result.lostAtFrame == 2)
        #expect(!result.skippedFrames.contains(3), "frames past the loss are untracked, not skipped")
    }

    @Test func framesWithNoDetectionAreReportedAsSkipped() {
        let result = EditorViewModel.assemble(
            samples: [sample(0, confidence: 0.9), sample(3, confidence: 0.9)],
            plan: plan(), mode: .hands, base: nil, clipStartFrame: 0, minimumConfidence: 0.3
        )
        #expect(result.track.keyframes.map(\.frame) == [0, 3])
        #expect(result.skippedFrames == [1, 2, 4], "gaps are named so the caller can decide to re-run")
    }

    @Test func keyframeFramesAreClipRelative() {
        let c = Clip(mediaRef: "m", startFrame: 100, durationFrames: 5)
        let p = TrackingPlan(target: c, subject: c, window: 100...104, step: 1)!
        let result = EditorViewModel.assemble(
            samples: (0..<5).map { sample($0, confidence: 0.9) },
            plan: p, mode: .hands, base: nil, clipStartFrame: 100, minimumConfidence: 0.3
        )
        #expect(result.track.keyframes.map(\.frame) == [0, 1, 2, 3, 4])
    }

    @Test func handsModeReplacesTheVerticesWithTheTrackedQuad() {
        let shape = EditorViewModel.shape(for: sample(0, confidence: 0.9), mode: .hands, base: nil)
        #expect(shape?.vertices.count == 4)
        #expect(shape?.vertices[1].x == 0.8)
    }

    /// Region mode keeps the drawn shape and rides the box, so a mask the user spent
    /// time on is moved, not replaced.
    @Test func regionModeMovesTheExistingPathRigidly() {
        let base = MaskShape(vertices: [
            MaskVertex(x: 0.4, y: 0.4), MaskVertex(x: 0.6, y: 0.4), MaskVertex(x: 0.5, y: 0.6),
        ])
        let moved = EditorViewModel.shape(
            for: SubjectTracker.Sample(
                frame: 0,
                points: [CGPoint(x: 0.7, y: 0.5), CGPoint(x: 1, y: 1)],   // centre, scale
                confidence: 0.9
            ),
            mode: .region, base: base
        )
        #expect(moved?.vertices.count == 3, "the path keeps its shape")
        // Centre was (0.5, 0.5); moving it to (0.7, 0.5) shifts every vertex by +0.2 in x.
        #expect(abs((moved?.vertices[0].x ?? 0) - 0.6) < 1e-9)
        #expect(abs((moved?.vertices[0].y ?? 0) - 0.4) < 1e-9)
    }

    @Test func regionModeScalesAboutTheTrackedCentre() {
        let base = MaskShape(vertices: [
            MaskVertex(x: 0.4, y: 0.4), MaskVertex(x: 0.6, y: 0.4), MaskVertex(x: 0.5, y: 0.6),
        ])
        let moved = EditorViewModel.shape(
            for: SubjectTracker.Sample(
                frame: 0, points: [CGPoint(x: 0.5, y: 0.5), CGPoint(x: 2, y: 2)], confidence: 0.9
            ),
            mode: .region, base: base
        )
        #expect(abs((moved?.vertices[0].x ?? 0) - 0.3) < 1e-9, "a doubled box doubles the offset from centre")
    }

    @Test func regionModeWithoutABaseShapeProducesNothing() {
        let moved = EditorViewModel.shape(
            for: SubjectTracker.Sample(
                frame: 0, points: [CGPoint(x: 0.5, y: 0.5), CGPoint(x: 1, y: 1)], confidence: 0.9
            ),
            mode: .region, base: nil
        )
        #expect(moved == nil)
    }
}

@Suite("Phase detection")
struct PhaseDetectorTests {

    /// A pinch-open-pinch-open clip: two approaches, so two boundaries.
    private var pinchTwice: [(frame: Int, span: Double)] {
        var out: [(Int, Double)] = []
        for f in 0..<20 { out.append((f, 0.02)) }          // closed
        for f in 20..<50 { out.append((f, 0.40)) }         // open
        for f in 50..<70 { out.append((f, 0.01)) }         // closed again
        for f in 70..<100 { out.append((f, 0.45)) }        // open again
        return out.map { (frame: $0.0, span: $0.1) }
    }

    @Test func findsOneBoundaryPerApproach() {
        let found = PhaseDetector.boundaries(spans: pinchTwice)
        #expect(found.count == 2)
        #expect(found[0].frame < 20)
        #expect(found[1].frame >= 50 && found[1].frame < 70)
    }

    @Test func reportsTheClosestFrameOfEachApproach() {
        var spans = pinchTwice
        spans[12] = (frame: 12, span: 0.004)   // the actual touch
        let found = PhaseDetector.boundaries(spans: spans)
        #expect(found.first?.frame == 12, "the minimum of the run, not its first frame")
    }

    /// Hands that stay apart the whole time have no phases; without this guard a clip
    /// of steady framing would report its own noise as boundaries.
    @Test func steadyFramingHasNoBoundaries() {
        let spans = (0..<100).map { (frame: $0, span: 0.40 + Double($0 % 3) * 0.005) }
        #expect(PhaseDetector.boundaries(spans: spans).isEmpty)
    }

    /// One wobbly pinch must not read as several: the hands have to open again first.
    @Test func aWobbleInsideOneApproachIsStillOneBoundary() {
        var spans: [(frame: Int, span: Double)] = []
        for f in 0..<10 { spans.append((f, 0.02)) }
        spans.append((10, 0.09))    // small jitter, nowhere near open
        for f in 11..<20 { spans.append((f, 0.02)) }
        for f in 20..<40 { spans.append((f, 0.40)) }
        #expect(PhaseDetector.boundaries(spans: spans).count == 1)
    }

    @Test func tooFewSamplesYieldNothing() {
        #expect(PhaseDetector.boundaries(spans: [(0, 0.1), (1, 0.4)]).isEmpty)
    }
}

@Suite("Phase shapes")
@MainActor
struct PhaseShapeTests {

    private func sample(_ frame: Int) -> SubjectTracker.Sample {
        SubjectTracker.Sample(
            frame: frame,
            points: [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.9, y: 0.1),
                     CGPoint(x: 0.9, y: 0.9), CGPoint(x: 0.1, y: 0.9)],
            confidence: 0.9, span: 0.5
        )
    }

    /// A phase is a vertex ORDER, so switching phases cannot change the count — the
    /// invariant the whole mask track depends on holds by construction.
    @Test func laterPhasesReorderTheSameFourPoints() {
        let c = Clip(mediaRef: "m", startFrame: 0, durationFrames: 20)
        let plan = TrackingPlan(target: c, subject: c, window: 0...19, step: 1)!
        let result = EditorViewModel.assemble(
            samples: (0..<20).map { sample($0) }, plan: plan, mode: .hands, base: nil,
            clipStartFrame: 0, minimumConfidence: 0.3,
            phaseShapes: [[0, 1, 2, 3], [0, 1, 3, 2]], boundaries: [10]
        )
        let before = result.track.keyframes.first { $0.frame == 5 }?.value
        let after = result.track.keyframes.first { $0.frame == 15 }?.value
        #expect(before?.vertices.count == 4)
        #expect(after?.vertices.count == 4, "the count is identical across the boundary")
        // Phase 2 swaps the last two corners, which is what crosses the path.
        #expect(after?.vertices[2].y == 0.9 && after?.vertices[2].x == 0.1)
        #expect(before?.vertices[2].x == 0.9)
    }

    @Test func withoutPhaseShapesEveryFrameUsesTheTrackedOrder() {
        let c = Clip(mediaRef: "m", startFrame: 0, durationFrames: 20)
        let plan = TrackingPlan(target: c, subject: c, window: 0...19, step: 1)!
        let result = EditorViewModel.assemble(
            samples: (0..<20).map { sample($0) }, plan: plan, mode: .hands, base: nil,
            clipStartFrame: 0, minimumConfidence: 0.3
        )
        let a = result.track.keyframes.first?.value
        let b = result.track.keyframes.last?.value
        #expect(a?.vertices.map(\.x) == b?.vertices.map(\.x))
    }
}

@Suite("Closed-hand collapse")
@MainActor
struct ClosedHandCollapseTests {

    private func sample(_ frame: Int, span: Double) -> SubjectTracker.Sample {
        SubjectTracker.Sample(
            frame: frame,
            points: [CGPoint(x: 0.2, y: 0.3), CGPoint(x: 0.8, y: 0.3),
                     CGPoint(x: 0.8, y: 0.7), CGPoint(x: 0.2, y: 0.7)],
            confidence: 0.9, span: span
        )
    }

    private func run(spans: [Double], closedSpan: Double?) -> KeyframeTrack<MaskShape> {
        let c = Clip(mediaRef: "m", startFrame: 0, durationFrames: spans.count)
        let plan = TrackingPlan(target: c, subject: c, window: 0...(spans.count - 1), step: 1)!
        return EditorViewModel.assemble(
            samples: spans.enumerated().map { sample($0.offset, span: $0.element) },
            plan: plan, mode: .hands, base: nil, clipStartFrame: 0,
            minimumConfidence: 0.3, closedSpan: closedSpan
        ).track
    }

    private func area(_ shape: MaskShape) -> Double {
        let v = shape.vertices
        guard v.count >= 3 else { return 0 }
        var sum = 0.0
        for i in v.indices {
            let a = v[i], b = v[(i + 1) % v.count]
            sum += a.x * b.y - b.x * a.y
        }
        return abs(sum) / 2
    }

    /// A pinch must draw nothing rather than the spike a near-degenerate quad makes.
    @Test func touchingFingertipsCollapseToZeroArea() {
        let track = run(spans: [0.5, 0.5, 0.01, 0.5], closedSpan: 0.1)
        #expect(area(track.keyframes[0].value) > 0.2)
        #expect(area(track.keyframes[2].value) == 0, "the closed frame encloses nothing")
    }

    /// The count is what the whole track depends on; collapsing must not touch it.
    @Test func collapsingKeepsTheVertexCount() {
        let track = run(spans: [0.5, 0.01], closedSpan: 0.1)
        #expect(track.keyframes.allSatisfy { $0.value.vertices.count == 4 })
    }

    @Test func collapsedVerticesShareTheCentreOfTheQuad() {
        let track = run(spans: [0.01], closedSpan: 0.1)
        let v = track.keyframes[0].value.vertices
        #expect(v.allSatisfy { abs($0.x - 0.5) < 1e-9 && abs($0.y - 0.5) < 1e-9 })
    }

    @Test func withoutAThresholdNothingCollapses() {
        let track = run(spans: [0.5, 0.01], closedSpan: nil)
        #expect(area(track.keyframes[1].value) > 0.2, "the raw quad is kept when the feature is off")
    }

    /// The same threshold drives both, so a phase can never start on a frame whose
    /// shape is still being drawn.
    @Test func theHideThresholdIsTheSameOneThatMarksPhases() {
        let spans = [0.5, 0.5, 0.01, 0.01, 0.5, 0.5]
        let threshold = PhaseDetector.closedThreshold(spans: spans)
        #expect(threshold != nil)
        let boundaries = PhaseDetector.boundaries(
            spans: spans.enumerated().map { (frame: $0.offset, span: $0.element) }
        )
        #expect(boundaries.count == 1)
        let track = run(spans: spans, closedSpan: threshold)
        #expect(area(track.keyframes[boundaries[0].frame].value) == 0)
    }
}

@Suite("Canonical corner order")
@MainActor
struct CanonicalOrderTests {

    private func crosses(_ v: [MaskVertex]) -> Bool {
        func intersects(_ p: MaskVertex, _ q: MaskVertex, _ r: MaskVertex, _ s: MaskVertex) -> Bool {
            func side(_ a: MaskVertex, _ b: MaskVertex, _ c: MaskVertex) -> Double {
                (c.y - a.y) * (b.x - a.x) - (b.y - a.y) * (c.x - a.x)
            }
            return (side(r, s, p) > 0) != (side(r, s, q) > 0)
                && (side(p, q, r) > 0) != (side(p, q, s) > 0)
        }
        return intersects(v[0], v[1], v[2], v[3]) || intersects(v[1], v[2], v[3], v[0])
    }

    private func shape(_ points: [CGPoint], order: [Int]? = nil) -> MaskShape {
        let c = Clip(mediaRef: "m", startFrame: 0, durationFrames: 1)
        let plan = TrackingPlan(target: c, subject: c, window: 0...0, step: 1)!
        return EditorViewModel.assemble(
            samples: [SubjectTracker.Sample(frame: 0, points: points, confidence: 0.9, span: 0.5)],
            plan: plan, mode: .hands, base: nil, clipStartFrame: 0, minimumConfidence: 0.3,
            phaseShapes: order.map { [$0] }, boundaries: []
        ).track.keyframes[0].value
    }

    /// The tracked order is semantic, not geometric — feeding it straight through let a
    /// phase flip between a quad and a bowtie as the hands turned.
    @Test func theBaseOrderAlwaysTracesASimpleQuad() {
        // Points deliberately supplied in an order that would self-intersect.
        let scrambled = [CGPoint(x: 0.2, y: 0.2), CGPoint(x: 0.8, y: 0.8),
                         CGPoint(x: 0.8, y: 0.2), CGPoint(x: 0.2, y: 0.8)]
        #expect(!crosses(shape(scrambled).vertices))
    }

    @Test func swappingTwoCornersAlwaysCrosses() {
        let square = [CGPoint(x: 0.2, y: 0.2), CGPoint(x: 0.8, y: 0.2),
                      CGPoint(x: 0.8, y: 0.8), CGPoint(x: 0.2, y: 0.8)]
        #expect(crosses(shape(square, order: [0, 1, 3, 2]).vertices))
        #expect(!crosses(shape(square, order: [0, 1, 2, 3]).vertices))
    }

    /// Repeating an index collapses a corner, so a phase can look like a triangle while
    /// the track keeps its four vertices.
    @Test func aRepeatedIndexCollapsesACornerIntoATriangle() {
        let square = [CGPoint(x: 0.2, y: 0.2), CGPoint(x: 0.8, y: 0.2),
                      CGPoint(x: 0.8, y: 0.8), CGPoint(x: 0.2, y: 0.8)]
        let tri = shape(square, order: [0, 1, 2, 2])
        #expect(tri.vertices.count == 4, "the count the track depends on is untouched")
        #expect(tri.vertices[2].x == tri.vertices[3].x && tri.vertices[2].y == tri.vertices[3].y)
    }
}
