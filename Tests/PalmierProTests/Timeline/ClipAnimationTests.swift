import Foundation
import Testing
@testable import PalmierPro

@Suite("Clip entrance and exit animations")
struct ClipAnimationTests {
    private func clip(
        in inAnimation: ClipAnimation? = nil,
        out outAnimation: ClipAnimation? = nil,
        duration: Int = 100
    ) -> Clip {
        var clip = Fixtures.clip(id: "c", mediaRef: "m", start: 10, duration: duration)
        clip.inAnimation = inAnimation
        clip.outAnimation = outAnimation
        return clip
    }

    private let fullFrame = Transform()
    private let leftHalf = Transform(centerX: 0.25, width: 0.5)

    @Test(arguments: [
        (ClipAnimation.Preset.slideLeft, ClipAnimator.Motion(dx: 1)),
        (.slideRight, ClipAnimator.Motion(dx: -1)),
        (.slideUp, ClipAnimator.Motion(dy: 1)),
        (.slideDown, ClipAnimator.Motion(dy: -1)),
        (.zoomIn, ClipAnimator.Motion(scale: 0.5, opacity: 0)),
        (.zoomOut, ClipAnimator.Motion(scale: 1.5, opacity: 0)),
    ])
    func entranceStartsAtTheFarEnd(preset: ClipAnimation.Preset, expected: ClipAnimator.Motion) {
        let c = clip(in: ClipAnimation(preset: preset, durationFrames: 20))
        #expect(ClipAnimator.motion(for: c, atOffset: 0, box: fullFrame) == expected)
        #expect(ClipAnimator.motion(for: c, atOffset: 20, box: fullFrame) == .identity)
    }

    @Test(arguments: [
        (ClipAnimation.Preset.slideLeft, ClipAnimator.Motion(dx: -1)),
        (.slideRight, ClipAnimator.Motion(dx: 1)),
        (.slideUp, ClipAnimator.Motion(dy: -1)),
        (.slideDown, ClipAnimator.Motion(dy: 1)),
        (.zoomIn, ClipAnimator.Motion(scale: 1.5, opacity: 0)),
        (.zoomOut, ClipAnimator.Motion(scale: 0.5, opacity: 0)),
    ])
    func exitEndsAtTheFarEndOnTheLastFrame(preset: ClipAnimation.Preset, expected: ClipAnimator.Motion) {
        let c = clip(out: ClipAnimation(preset: preset, durationFrames: 20))
        #expect(ClipAnimator.motion(for: c, atOffset: 79, box: fullFrame) == .identity)
        #expect(ClipAnimator.motion(for: c, atOffset: 99, box: fullFrame) == expected)
    }

    @Test func slideTravelsOnlyAsFarAsTheBoxNeedsToLeaveTheCanvas() {
        let c = clip(
            in: ClipAnimation(preset: .slideRight, durationFrames: 20),
            out: ClipAnimation(preset: .slideLeft, durationFrames: 20)
        )
        #expect(ClipAnimator.motion(for: c, atOffset: 0, box: leftHalf).dx == -0.5)
        #expect(ClipAnimator.motion(for: c, atOffset: 99, box: leftHalf).dx == -0.5)
    }

    @Test func presentedTransformMovesWhileEditingGeometryStaysPut() {
        let c = clip(out: ClipAnimation(preset: .slideRight, durationFrames: 20))
        let lastFrame = c.startFrame + 99
        #expect(c.presentedTransformAt(frame: lastFrame).centerX == 1.5)
        #expect(c.transformAt(frame: lastFrame).centerX == 0.5)
    }

    @Test func zoomFadesTheRenderedOpacity() {
        let c = clip(in: ClipAnimation(preset: .zoomIn, durationFrames: 20))
        #expect(c.opacityAt(frame: c.startFrame) == 0)
        #expect(c.opacityAt(frame: c.startFrame + 20) == 1)
    }

    @Test func clampShortensTheExitBeforeTheEntranceAndDropsEmptyAnimations() {
        var c = clip(
            in: ClipAnimation(preset: .zoomIn, durationFrames: 30),
            out: ClipAnimation(preset: .slideLeft, durationFrames: 30)
        )
        c.setDuration(40)
        #expect(c.inAnimation?.durationFrames == 30)
        #expect(c.outAnimation?.durationFrames == 10)
        c.setDuration(25)
        #expect(c.inAnimation?.durationFrames == 25)
        #expect(c.outAnimation == nil)
    }

    @Test func animationsRoundTripThroughCoding() throws {
        let c = clip(
            in: ClipAnimation(preset: .slideUp, durationFrames: 12),
            out: ClipAnimation(preset: .zoomOut, durationFrames: 8)
        )
        let decoded = try JSONDecoder().decode(Clip.self, from: JSONEncoder().encode(c))
        #expect(decoded.inAnimation == c.inAnimation)
        #expect(decoded.outAnimation == c.outAnimation)
    }
}

@Suite("Clip animations through editing")
@MainActor
struct ClipAnimationEditingTests {
    @Test func splitKeepsTheEntranceOnTheHeadAndTheExitOnTheTail() async throws {
        var clip = Fixtures.clip(id: "c", mediaRef: "m", start: 0, duration: 100)
        clip.inAnimation = ClipAnimation(preset: .slideLeft, durationFrames: 10)
        clip.outAnimation = ClipAnimation(preset: .slideRight, durationFrames: 10)
        let h = ToolHarness(timeline: Fixtures.timeline(tracks: [Fixtures.videoTrack(clips: [clip])]))

        _ = try await h.runOK("split_clips", args: ["splits": [["clipId": "c", "atFrame": 50]]])

        let clips = h.editor.timeline.tracks[0].clips.sorted { $0.startFrame < $1.startFrame }
        #expect(clips.map(\.inAnimation?.preset) == [.slideLeft, nil])
        #expect(clips.map(\.outAnimation?.preset) == [nil, .slideRight])
    }

    @Test func splittingATitleDoesNotReplayItsEntranceOnTheTail() async throws {
        var title = Fixtures.clip(id: "t", mediaRef: "text", mediaType: .text, start: 0, duration: 100)
        title.textContent = "Title"
        title.textStyle = TextStyle()
        title.textAnimation = TextAnimation(preset: .popIn, durationFrames: 30)
        let h = ToolHarness(timeline: Fixtures.timeline(tracks: [Fixtures.videoTrack(clips: [title])]))

        _ = try await h.runOK("split_clips", args: ["splits": [["clipId": "t", "atFrame": 50]]])

        let clips = h.editor.timeline.tracks[0].clips.sorted { $0.startFrame < $1.startFrame }
        #expect(clips.map(\.textAnimation?.preset) == [.popIn, nil])
    }

    @Test func nestedWindowStartingMidChildDropsTheChildsOpeningAnimations() {
        var title = Fixtures.clip(id: "t", mediaRef: "text", mediaType: .text, start: 0, duration: 180)
        title.textAnimation = TextAnimation(preset: .popIn, durationFrames: 54)
        var image = Fixtures.clip(id: "i", mediaRef: "m", mediaType: .image, start: 0, duration: 180)
        image.inAnimation = ClipAnimation(preset: .zoomIn, durationFrames: 30)
        image.outAnimation = ClipAnimation(preset: .zoomOut, durationFrames: 30)
        let child = Fixtures.timeline(tracks: [Fixtures.videoTrack(clips: [title, image])])
        var carrier = Fixtures.clip(id: "n", mediaRef: child.id, mediaType: .sequence, start: 54, duration: 60)
        carrier.trimStartFrame = 54

        let remapped = NestFlattener.flatten(carrier: carrier, child: child, visual: true).videoTracks.flatMap { $0 }

        #expect(remapped.allSatisfy { $0.textAnimation == nil && $0.inAnimation == nil && $0.outAnimation == nil })
    }
}
