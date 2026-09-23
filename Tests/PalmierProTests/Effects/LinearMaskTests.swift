import Foundation
import Testing
@testable import PalmierPro

struct LinearMaskTests {
    @Test func nativeFeatherDirectionAndInverse() throws {
        let mask = LinearMaskGeometry(rotation: -90)
        func alpha(_ x: Double, inverse: Bool = false) -> Double {
            mask.alpha(x: x, y: 0.5, aspect: 1080.0 / 608, feather: 0.6, inverted: inverse)
        }
        #expect(alpha(0) == 1)
        #expect(abs(alpha(0.5) - 0.5) < 0.00001)
        #expect(alpha(1) == 0)
        #expect(abs(alpha(0.45) + alpha(0.45, inverse: true) - 1) < 0.00001)
        let shape = MaskShape(linear: mask, feather: 0.6)
        #expect(shape.isRenderable)
        #expect(try JSONDecoder().decode(MaskShape.self, from: JSONEncoder().encode(shape)) == shape)
        let halfway = MaskShape.keyframeInterpolate(shape,
            MaskShape(linear: .init(centerX: 0.4, rotation: -30), feather: 0.2), t: 0.5)
        #expect(halfway.linear?.rotation == -60)
        #expect(halfway.linear?.centerX == 0.2)
        #expect(abs(halfway.feather - 0.4) < 0.00001)
    }
}
