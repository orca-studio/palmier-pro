import AppKit
import SwiftUI

/// Pen tool and vertex handles for a clip's path mask.
///
/// Two modes on one overlay: with no mask yet, clicks drop draft points and the path
/// closes on Return or by clicking the first point. Once a mask exists, the same view
/// shows its anchors and drags them — the drag routes through `applyMaskShape`, so a
/// live keyframe track gets a keyframe at the playhead instead of losing its animation.
struct MaskOverlayView: View {
    @Environment(EditorViewModel.self) var editor

    private let handleSize: CGFloat = AppTheme.Spacing.smMd
    private let lineColor = AppTheme.Accent.timecodeColor
    private let draftColor = AppTheme.Accent.timecodeColor.opacity(AppTheme.Opacity.strong)

    @State private var draft: [CGPoint] = []
    @State private var dragStart: MaskShape?

    var body: some View {
        GeometryReader { geo in
            let videoRect = videoContentRect(in: geo.size)
            if let clip = editor.maskEditableClip {
                let shape = clip.maskAt(frame: editor.activeFrame)
                ZStack {
                    Canvas { ctx, _ in
                        if let shape {
                            ctx.stroke(outline(shape.vertices.map { CGPoint(x: $0.x, y: $0.y) }, in: videoRect, closed: true),
                                       with: .color(lineColor), lineWidth: AppTheme.BorderWidth.medium)
                        } else if draft.count >= 2 {
                            ctx.stroke(outline(draft, in: videoRect, closed: false),
                                       with: .color(draftColor), lineWidth: AppTheme.BorderWidth.medium)
                        }
                    }
                    .allowsHitTesting(false)

                    // Click target for the pen. Sits under the handles so an existing
                    // anchor always wins the hit.
                    if shape == nil {
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .onTapGesture { location in
                                addDraftPoint(location, videoRect: videoRect, clipId: clip.id)
                            }
                            .onHover { $0 ? NSCursor.crosshair.push() : NSCursor.pop() }
                    }

                    if let shape {
                        ForEach(Array(shape.vertices.enumerated()), id: \.offset) { index, vertex in
                            let pos = screenPoint(CGPoint(x: vertex.x, y: vertex.y), in: videoRect)
                            Circle()
                                .fill(lineColor)
                                .frame(width: handleSize, height: handleSize)
                                .position(pos)
                                .onHover { $0 ? NSCursor.openHand.push() : NSCursor.pop() }
                                .gesture(vertexDrag(clip: clip, shape: shape, index: index, videoRect: videoRect))
                                .contextMenu {
                                    Button("Add Point After") { editor.insertMaskVertex(clipId: clip.id, afterIndex: index) }
                                    Button("Delete Point") { editor.removeMaskVertex(clipId: clip.id, index: index) }
                                        .disabled(shape.vertices.count <= 3)
                                }
                        }
                    } else if !draft.isEmpty {
                        ForEach(Array(draft.enumerated()), id: \.offset) { _, point in
                            Circle()
                                .fill(draftColor)
                                .frame(width: handleSize, height: handleSize)
                                .position(screenPoint(point, in: videoRect))
                                .allowsHitTesting(false)
                        }
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .allowsHitTesting(editor.maskEditableClip != nil)
        .onChange(of: editor.maskEditingActive) { _, active in
            if !active { draft = [] }
        }
        .onChange(of: editor.selectedClipIds) { _, _ in draft = [] }
    }

    // MARK: - Pen

    private func addDraftPoint(_ location: CGPoint, videoRect: CGRect, clipId: String) {
        let point = normalizedPoint(location, in: videoRect)
        // Clicking the first point closes the path — the standard pen-tool gesture.
        if draft.count >= 3, let first = draft.first,
           hypot(first.x - point.x, first.y - point.y) < 0.02 {
            editor.commitMaskDraft(clipId: clipId, points: draft)
            draft = []
            return
        }
        draft.append(point)
    }

    // MARK: - Drag

    private func vertexDrag(clip: Clip, shape: MaskShape, index: Int, videoRect: CGRect) -> some Gesture {
        DragGesture(coordinateSpace: .local)
            .onChanged { value in
                if dragStart == nil { dragStart = shape }
                guard let start = dragStart else { return }
                editor.applyMaskShape(clipId: clip.id, shape: moved(start, index: index, to: value.location, videoRect: videoRect))
            }
            .onEnded { value in
                guard let start = dragStart else { return }
                dragStart = nil
                editor.commitMaskShape(clipId: clip.id, shape: moved(start, index: index, to: value.location, videoRect: videoRect))
            }
    }

    private func moved(_ shape: MaskShape, index: Int, to location: CGPoint, videoRect: CGRect) -> MaskShape {
        var out = shape
        guard index < out.vertices.count else { return out }
        let p = normalizedPoint(location, in: videoRect)
        out.vertices[index].point = AnimPair(a: Double(p.x), b: Double(p.y))
        return out
    }

    // MARK: - Geometry

    /// Mask coordinates are 0–1 of the SOURCE box. The overlay only handles the
    /// identity-transform case exactly; a transformed clip still edits correctly
    /// because the same mapping is used in both directions.
    private func screenPoint(_ p: CGPoint, in videoRect: CGRect) -> CGPoint {
        CGPoint(x: videoRect.minX + p.x * videoRect.width, y: videoRect.minY + p.y * videoRect.height)
    }

    private func normalizedPoint(_ p: CGPoint, in videoRect: CGRect) -> CGPoint {
        CGPoint(
            x: min(1, max(0, (p.x - videoRect.minX) / max(1, videoRect.width))),
            y: min(1, max(0, (p.y - videoRect.minY) / max(1, videoRect.height)))
        )
    }

    private func outline(_ points: [CGPoint], in videoRect: CGRect, closed: Bool) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: screenPoint(first, in: videoRect))
        for p in points.dropFirst() { path.addLine(to: screenPoint(p, in: videoRect)) }
        if closed { path.closeSubpath() }
        return path
    }

    private func videoContentRect(in viewSize: CGSize) -> CGRect {
        let videoAspect = CGFloat(editor.timeline.width) / CGFloat(editor.timeline.height)
        let viewAspect = viewSize.width / viewSize.height
        let w: CGFloat, h: CGFloat
        if viewAspect > videoAspect {
            h = viewSize.height; w = h * videoAspect
        } else {
            w = viewSize.width; h = w / videoAspect
        }
        return CGRect(x: (viewSize.width - w) / 2, y: (viewSize.height - h) / 2, width: w, height: h)
    }
}
