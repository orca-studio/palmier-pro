import AppKit
import Testing
@testable import PalmierPro

@Suite("Timeline accessibility elements")
@MainActor
struct TimelineAccessibilityTests {
    private func makeView(clips: [Clip] = [Fixtures.clip(id: "a", start: 0, duration: 30), Fixtures.clip(id: "b", start: 30, duration: 30)]) -> (TimelineView, EditorViewModel) {
        let editor = EditorViewModel()
        editor.timeline = Fixtures.timeline(tracks: [Fixtures.videoTrack(clips: clips)])
        let view = TimelineView(editor: editor)
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 200)
        return (view, editor)
    }

    private func element(_ id: String, in view: TimelineView) -> NSAccessibilityElement? {
        func search(_ items: [Any]) -> NSAccessibilityElement? {
            for case let item as NSAccessibilityElement in items {
                if item.accessibilityIdentifier() == id { return item }
                if let found = search(item.accessibilityChildren() ?? []) { return found }
            }
            return nil
        }
        return search(view.accessibilityChildren() ?? [])
    }

    @Test func tracksAndClipsAreIdentifiedElements() throws {
        let (view, editor) = makeView()
        let trackId = editor.timeline.tracks[0].id

        let lane = try #require(element("timeline.track.\(trackId).lane", in: view))
        #expect(lane.accessibilityRole() == .group)
        #expect(lane.accessibilityChildren()?.count == 2)
        #expect(element("timeline.clip.a", in: view)?.accessibilityRole() == .button)
    }

    @Test func pressingAClipSelectsItLikeAPlainClick() throws {
        let (view, editor) = makeView()
        editor.selectedClipIds = ["b"]

        let clip = try #require(element("timeline.clip.a", in: view))
        #expect(clip.accessibilityPerformPress())

        #expect(editor.selectedClipIds == ["a"])
        #expect(clip.isAccessibilitySelected())
    }

    @Test func elementsFollowTimelineEdits() throws {
        let (view, editor) = makeView()
        #expect(element("timeline.clip.b", in: view) != nil)

        editor.timeline.tracks[0].clips.removeAll { $0.id == "b" }

        #expect(element("timeline.clip.b", in: view) == nil)
    }

    @Test func playheadSeeksByTimecodeAndByFrame() throws {
        let (view, editor) = makeView()
        let playhead = try #require(element("timeline.playhead", in: view))

        playhead.setAccessibilityValue("00:00:01:00")
        #expect(editor.activeFrame == 30)
        #expect(playhead.accessibilityPerformIncrement())
        #expect(editor.activeFrame == 31)
        #expect(playhead.accessibilityValue() as? String == "00:00:01:01")
    }
}
