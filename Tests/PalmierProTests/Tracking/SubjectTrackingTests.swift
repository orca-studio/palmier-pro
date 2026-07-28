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
