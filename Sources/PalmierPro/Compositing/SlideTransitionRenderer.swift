import CoreImage

/// Horizontal slide with quintic ease-out and a moving ten-percent black separator.
enum SlideTransitionRenderer {
    static func render(from: CIImage, to: CIImage, progress: Double, extent: CGRect) -> CIImage {
        guard progress.isFinite else { return from.cropped(to: extent) }
        let p = min(1, max(0, progress))
        if p == 0 { return from.cropped(to: extent) }
        if p == 1 { return to.cropped(to: extent) }
        let eased = 1 - pow(1 - p, 5)
        let offset = extent.width * eased
        let outgoing = from.cropped(to: extent).transformed(by: .init(translationX: -offset, y: 0))
        let incoming = to.cropped(to: extent).transformed(by: .init(translationX: extent.width - offset, y: 0))
        let band = CGRect(x: extent.minX + extent.width * (1 - eased * 1.1),
                          y: extent.minY, width: extent.width * 0.1, height: extent.height)
        return CIImage(color: .black).cropped(to: band)
            .composited(over: incoming.composited(over: outgoing)).cropped(to: extent)
    }
}
