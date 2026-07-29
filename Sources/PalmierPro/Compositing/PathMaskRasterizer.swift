import CoreGraphics
import CoreImage
import Foundation

/// Turns a `MaskShape` into an alpha mask and applies it to a clip's image.
///
/// Not a CIKernel like the other masks here: `EdgeRoundingKernel` computes a
/// rounded-rect distance field, which is closed-form per pixel. An arbitrary
/// bezier path is not — a kernel would have to walk every segment for every
/// pixel. Core Graphics already rasterizes paths in hardware, so the path is
/// filled into a one-channel bitmap once per frame and used as a blend mask.
enum PathMaskRasterizer {

    /// Rasterized masks are reused while the path holds still — the common case,
    /// where only a static shape is set. An animated track changes the key every
    /// frame and simply misses; the cost is then one path fill per rendered frame.
    private static let cache = MaskCache()

    /// Applies `shape` to `image`, cutting away everything outside the path.
    /// `extent` is the image's current source-pixel rect (post-crop).
    static func apply(_ image: CIImage, shape: MaskShape, extent: CGRect) -> CIImage {
        guard shape.isRenderable, extent.width >= 1, extent.height >= 1 else { return image }
        guard let mask = cache.mask(for: shape, extent: extent) else { return image }

        // Blend against fully transparent rather than clipping: feathered edges need
        // partial alpha, which a hard crop cannot express.
        let clear = CIImage(color: .clear).cropped(to: extent)
        return image.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: clear,
            kCIInputMaskImageKey: mask,
        ])
    }

    /// Path in the image's own pixel space. Vertex coordinates are 0–1 of the
    /// source display box, y-down; Core Image is y-up, so y is mirrored here and
    /// nowhere else.
    static func path(for shape: MaskShape, extent: CGRect) -> CGPath {
        let path = CGMutablePath()
        let pts = shape.vertices
        guard pts.count >= 3 else { return path }

        func position(_ v: MaskVertex) -> CGPoint {
            CGPoint(
                x: extent.minX + CGFloat(v.x) * extent.width,
                y: extent.minY + CGFloat(1 - v.y) * extent.height
            )
        }
        func offset(_ base: CGPoint, _ delta: AnimPair?) -> CGPoint? {
            guard let delta else { return nil }
            return CGPoint(
                x: base.x + CGFloat(delta.a) * extent.width,
                y: base.y - CGFloat(delta.b) * extent.height
            )
        }

        path.move(to: position(pts[0]))
        for i in 0..<pts.count {
            let from = pts[i]
            let to = pts[(i + 1) % pts.count]
            let start = position(from), end = position(to)
            let c1 = offset(start, from.outControl)
            let c2 = offset(end, to.inControl)
            switch (c1, c2) {
            case let (c1?, c2?): path.addCurve(to: end, control1: c1, control2: c2)
            case let (c1?, nil): path.addQuadCurve(to: end, control: c1)
            case let (nil, c2?): path.addQuadCurve(to: end, control: c2)
            case (nil, nil):     path.addLine(to: end)
            }
        }
        path.closeSubpath()
        return path
    }
}

/// Bounded, key-complete cache. The key carries everything the bitmap depends on,
/// so a hit can never return a mask built for a different path or size.
private final class MaskCache: @unchecked Sendable {
    private struct Key: Hashable {
        let shape: Data
        let width: Int
        let height: Int
        let originX: Int
        let originY: Int
    }

    private let lock = NSLock()
    private var entries: [Key: CIImage] = [:]
    private var order: [Key] = []
    private static let capacity = 24

    func mask(for shape: MaskShape, extent: CGRect) -> CIImage? {
        guard let encoded = try? JSONEncoder().encode(shape) else { return nil }
        let key = Key(
            shape: encoded,
            width: Int(extent.width.rounded()), height: Int(extent.height.rounded()),
            originX: Int(extent.minX.rounded()), originY: Int(extent.minY.rounded())
        )
        lock.lock()
        if let hit = entries[key] {
            lock.unlock()
            return hit
        }
        lock.unlock()

        guard let built = MaskCache.render(shape: shape, extent: extent) else { return nil }
        lock.lock()
        if entries[key] == nil {
            entries[key] = built
            order.append(key)
            while order.count > MaskCache.capacity {
                entries.removeValue(forKey: order.removeFirst())
            }
        }
        lock.unlock()
        return built
    }

    private static func render(shape: MaskShape, extent: CGRect) -> CIImage? {
        let w = max(1, Int(extent.width.rounded())), h = max(1, Int(extent.height.rounded()))
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        ctx.setFillColor(gray: shape.inverted ? 1 : 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setFillColor(gray: shape.inverted ? 0 : 1, alpha: 1)
        // Render into a local origin; the caller's extent origin is folded back below.
        let local = CGRect(x: 0, y: 0, width: extent.width, height: extent.height)
        ctx.addPath(PathMaskRasterizer.path(for: shape, extent: local))
        ctx.fillPath(using: .evenOdd)

        guard let cg = ctx.makeImage() else { return nil }
        var mask = CIImage(cgImage: cg).transformed(
            by: CGAffineTransform(translationX: extent.minX, y: extent.minY)
        )
        if shape.feather > 0 {
            // Feather reads as a fraction of the shorter side so it looks the same
            // on any source resolution.
            let radius = shape.feather * Double(min(w, h)) / 2
            if radius >= 0.5 {
                mask = mask
                    .clampedToExtent()
                    .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
                    .cropped(to: extent)
            }
        }
        return mask
    }
}
