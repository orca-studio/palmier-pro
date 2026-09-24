import AppKit

/// Accessibility stand-in for content the timeline draws itself; geometry and state are read at query time.
final class TimelineAccessibilityElement: NSAccessibilityElement {
    weak var hostView: NSView?
    var rectInHost: () -> NSRect? = { nil }
    var isSelectedProvider: (() -> Bool)?
    var valueProvider: (() -> Any?)?
    var press: (() -> Bool)?
    var increment: (() -> Void)?
    var decrement: (() -> Void)?
    var setValue: ((Any?) -> Void)?
    var elementChildren: [Any]?

    override func accessibilityFrame() -> NSRect {
        guard let hostView, let rect = rectInHost() else { return .zero }
        return NSAccessibility.screenRect(fromView: hostView, rect: rect)
    }

    override func isAccessibilitySelected() -> Bool { isSelectedProvider?() ?? false }
    override func accessibilityValue() -> Any? { valueProvider?() }
    override func accessibilityChildren() -> [Any]? { elementChildren }
    override func accessibilityPerformPress() -> Bool { press?() ?? false }

    override func accessibilityPerformIncrement() -> Bool {
        guard let increment else { return false }
        increment()
        return true
    }

    override func accessibilityPerformDecrement() -> Bool {
        guard let decrement else { return false }
        decrement()
        return true
    }

    override func isAccessibilitySelectorAllowed(_ selector: Selector) -> Bool {
        if selector == #selector(setAccessibilityValue(_:)) { return setValue != nil }
        return super.isAccessibilitySelectorAllowed(selector)
    }

    override func setAccessibilityValue(_ value: Any?) {
        setValue?(value)
    }
}

/// Elements rebuilt only when the active timeline's content changes.
struct TimelineAccessibilityCache {
    let timelineId: String
    let revision: Int
    let elements: [Any]
}

extension TimelineView {
    func timelineAccessibilityElements() -> [Any] {
        let timelineId = editor.activeTimelineId
        let revision = editor.timelineRenderRevision
        if let cache = timelineAccessibilityCache, cache.timelineId == timelineId, cache.revision == revision {
            return cache.elements
        }
        let elements: [Any] = [makePlayheadElement()] + editor.timeline.tracks.map(makeTrackElement)
        timelineAccessibilityCache = TimelineAccessibilityCache(
            timelineId: timelineId, revision: revision, elements: elements
        )
        return elements
    }

    private func trackIndex(of trackId: String) -> Int? {
        editor.timeline.tracks.firstIndex { $0.id == trackId }
    }

    private func makeTrackElement(_ track: Track) -> TimelineAccessibilityElement {
        let trackId = track.id
        let element = TimelineAccessibilityElement()
        element.hostView = self
        element.setAccessibilityParent(self)
        element.setAccessibilityRole(.group)
        element.setAccessibilityIdentifier("timeline.track.\(trackId).lane")
        if let index = trackIndex(of: trackId) {
            element.setAccessibilityLabel(editor.timelineTrackDisplayLabel(at: index))
        }
        element.rectInHost = { [weak self] in
            guard let self, let index = self.trackIndex(of: trackId) else { return nil }
            let geometry = self.geometry
            return NSRect(
                x: geometry.headerWidth,
                y: geometry.trackY(at: index),
                width: max(0, self.bounds.width - geometry.headerWidth),
                height: geometry.trackHeight(at: index)
            )
        }
        element.elementChildren = track.clips.map { makeClipElement($0, parent: element) }
        return element
    }

    private func makeClipElement(_ clip: Clip, parent: TimelineAccessibilityElement) -> TimelineAccessibilityElement {
        let clipId = clip.id
        let fps = editor.timeline.fps
        let element = TimelineAccessibilityElement()
        element.hostView = self
        element.setAccessibilityParent(parent)
        element.setAccessibilityRole(.button)
        element.setAccessibilityIdentifier("timeline.clip.\(clipId)")
        element.setAccessibilityLabel(editor.clipDisplayLabel(for: clip))
        element.setAccessibilityHelp(
            "\(formatTimecode(frame: clip.startFrame, fps: fps)) – \(formatTimecode(frame: clip.endFrame, fps: fps))"
        )
        element.rectInHost = { [weak self] in
            guard let self, let location = self.editor.findClip(id: clipId) else { return nil }
            let clip = self.editor.timeline.tracks[location.trackIndex].clips[location.clipIndex]
            return self.geometry.clipRect(for: clip, trackIndex: location.trackIndex)
        }
        element.isSelectedProvider = { [weak self] in
            self?.editor.selectedClipIds.contains(clipId) ?? false
        }
        element.press = { [weak self] in
            guard let self, self.editor.findClip(id: clipId) != nil else { return false }
            self.editor.selectTimelineClip(clipId)
            return true
        }
        return element
    }

    private func makePlayheadElement() -> TimelineAccessibilityElement {
        let element = TimelineAccessibilityElement()
        element.hostView = self
        element.setAccessibilityParent(self)
        element.setAccessibilityRole(.slider)
        element.setAccessibilityIdentifier("timeline.playhead")
        element.setAccessibilityLabel(L10n.string("Playhead"))
        element.rectInHost = { [weak self] in
            guard let self else { return nil }
            let geometry = self.geometry
            let x = geometry.headerWidth + Double(self.editor.activeFrame) * geometry.pixelsPerFrame
            return NSRect(x: x, y: 0, width: 1, height: self.bounds.height)
        }
        element.valueProvider = { [weak self] in
            guard let self else { return nil }
            return formatTimecode(frame: self.editor.activeFrame, fps: self.editor.timeline.fps)
        }
        element.increment = { [weak self] in
            guard let self else { return }
            self.editor.seekToFrame(self.editor.activeFrame + 1)
        }
        element.decrement = { [weak self] in
            guard let self else { return }
            self.editor.seekToFrame(self.editor.activeFrame - 1)
        }
        element.setValue = { [weak self] value in
            guard let self, let text = value as? String,
                  let frame = parseTimecode(text, fps: self.editor.timeline.fps) else { return }
            self.editor.seekToFrame(frame)
        }
        return element
    }
}
