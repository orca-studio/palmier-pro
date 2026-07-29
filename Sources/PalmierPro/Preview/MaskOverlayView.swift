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
                let frame = editor.activeFrame
                let transform = clip.transformAt(frame: frame)
                // Mask coordinates are 0–1 of the CROPPED source, because the mask runs
                // after crop in the render pipeline. Handles must land on that same rect.
                let maskRect = maskContentRect(clip: clip, transform: transform, frame: frame, videoRect: videoRect)
                let shape = clip.maskAt(frame: frame)
                ZStack {
                    Canvas { ctx, _ in
                        if let shape {
                            ctx.stroke(outline(shape.vertices.map { CGPoint(x: $0.x, y: $0.y) }, in: maskRect, transform: transform, closed: true),
                                       with: .color(lineColor), lineWidth: AppTheme.BorderWidth.medium)
                        } else if draft.count >= 2 {
                            ctx.stroke(outline(draft, in: maskRect, transform: transform, closed: false),
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
                                addDraftPoint(location, rect: maskRect, transform: transform, clipId: clip.id)
                            }
                            .onHover { $0 ? NSCursor.crosshair.push() : NSCursor.pop() }
                    }

                    if let shape {
                        ForEach(Array(shape.vertices.enumerated()), id: \.offset) { index, vertex in
                            let pos = screenPoint(CGPoint(x: vertex.x, y: vertex.y), in: maskRect, transform: transform)
                            Circle()
                                .fill(lineColor)
                                .frame(width: handleSize, height: handleSize)
                                .position(pos)
                                .onHover { $0 ? NSCursor.openHand.push() : NSCursor.pop() }
                                .gesture(vertexDrag(clip: clip, shape: shape, index: index, rect: maskRect, transform: transform))
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
                                .position(screenPoint(point, in: maskRect, transform: transform))
                                .allowsHitTesting(false)
                        }
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                // Rotate with the clip; gestures then arrive in the clip's own axes.
                .rotationEffect(
                    .degrees(transform.rotation),
                    anchor: UnitPoint(x: maskRect.midX / max(1, geo.size.width),
                                      y: maskRect.midY / max(1, geo.size.height))
                )
            }
        }
        .allowsHitTesting(editor.maskEditableClip != nil)
        .onChange(of: editor.maskEditingActive) { _, active in
            if !active { draft = [] }
        }
        .onChange(of: editor.selectedClipIds) { _, _ in draft = [] }
    }

    // MARK: - Pen

    private func addDraftPoint(_ location: CGPoint, rect: CGRect, transform: Transform, clipId: String) {
        let point = normalizedPoint(location, in: rect, transform: transform)
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

    private func vertexDrag(clip: Clip, shape: MaskShape, index: Int, rect: CGRect, transform: Transform) -> some Gesture {
        DragGesture(coordinateSpace: .local)
            .onChanged { value in
                if dragStart == nil { dragStart = shape }
                guard let start = dragStart else { return }
                editor.applyMaskShape(clipId: clip.id, shape: moved(start, index: index, to: value.location, rect: rect, transform: transform))
            }
            .onEnded { value in
                guard let start = dragStart else { return }
                dragStart = nil
                editor.commitMaskShape(clipId: clip.id, shape: moved(start, index: index, to: value.location, rect: rect, transform: transform))
            }
    }

    private func moved(_ shape: MaskShape, index: Int, to location: CGPoint, rect: CGRect, transform: Transform) -> MaskShape {
        var out = shape
        guard index < out.vertices.count else { return out }
        let p = normalizedPoint(location, in: rect, transform: transform)
        out.vertices[index].point = AnimPair(a: Double(p.x), b: Double(p.y))
        return out
    }

    // MARK: - Geometry

    /// Where the masked content actually lands on the canvas: the clip's placed rect,
    /// narrowed by its crop. Rotation is not folded in here — the whole overlay is
    /// rotated instead, so gestures arrive already in the clip's own axes.
    private func maskContentRect(clip: Clip, transform: Transform, frame: Int, videoRect: CGRect) -> CGRect {
        let topLeft = transform.topLeft
        let clipRect = CGRect(
            x: videoRect.minX + topLeft.x * videoRect.width,
            y: videoRect.minY + topLeft.y * videoRect.height,
            width: transform.width * videoRect.width,
            height: transform.height * videoRect.height
        )
        let crop = clip.cropAt(frame: frame)
        guard !crop.isIdentity else { return clipRect }
        return CGRect(
            x: clipRect.minX + crop.left * clipRect.width,
            y: clipRect.minY + crop.top * clipRect.height,
            width: max(1, crop.visibleWidthFraction * clipRect.width),
            height: max(1, crop.visibleHeightFraction * clipRect.height)
        )
    }

    /// Flips happen in the transform, after the mask, so a mirrored clip shows a
    /// mirrored path — the handles have to mirror with it or they grab the wrong side.
    private func screenPoint(_ p: CGPoint, in rect: CGRect, transform: Transform) -> CGPoint {
        let x = transform.flipHorizontal ? 1 - p.x : p.x
        let y = transform.flipVertical ? 1 - p.y : p.y
        return CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
    }

    private func normalizedPoint(_ p: CGPoint, in rect: CGRect, transform: Transform) -> CGPoint {
        var x = (p.x - rect.minX) / max(1, rect.width)
        var y = (p.y - rect.minY) / max(1, rect.height)
        if transform.flipHorizontal { x = 1 - x }
        if transform.flipVertical { y = 1 - y }
        return CGPoint(x: min(1, max(0, x)), y: min(1, max(0, y)))
    }

    private func outline(_ points: [CGPoint], in rect: CGRect, transform: Transform, closed: Bool) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: screenPoint(first, in: rect, transform: transform))
        for p in points.dropFirst() { path.addLine(to: screenPoint(p, in: rect, transform: transform)) }
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
