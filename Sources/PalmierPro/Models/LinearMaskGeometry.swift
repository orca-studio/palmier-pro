import Foundation

struct LinearMaskGeometry: Codable, Sendable, Equatable {
    var centerX: Double = 0
    var centerY: Double = 0
    var rotation: Double = 0

    var isFinite: Bool { centerX.isFinite && centerY.isFinite && rotation.isFinite }

    func alpha(x: Double, y: Double, aspect: Double, feather: Double, inverted: Bool) -> Double {
        let angle = -rotation * .pi / 180
        let distance = -sin(angle) * ((x - 0.5) * 2 - centerX) * aspect
            + cos(angle) * ((y - 0.5) * 2 - centerY)
        let period = Double.pi / 2
        let phase = (angle - floor(angle / period) * period) / (Double.pi / 4) - 1
        let decay = pow(max(0, 1 - phase * phase), 0.125)
        let lower = -0.005 * decay - feather
        let span = feather - lower
        let t = span > 1e-12 ? min(1, max(0, (distance - lower) / span)) : (distance >= 0 ? 1.0 : 0.0)
        let alpha = t * t * (3 - 2 * t)
        return inverted ? 1 - alpha : alpha
    }
}
