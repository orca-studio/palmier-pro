import CoreImage
import Foundation
import Testing
@testable import PalmierPro

@Suite("detail.enhance")
struct EnhanceEffectTests {
    private let extent = CGRect(x: 0, y: 0, width: 64, height: 64)

    /// A soft edge plus fine checker noise, so sharpening and denoising both have something to change.
    private func source() -> CIImage {
        let gradient = CIFilter(name: "CILinearGradient", parameters: [
            "inputPoint0": CIVector(x: 0, y: 0), "inputPoint1": CIVector(x: 64, y: 0),
            "inputColor0": CIColor(red: 0.2, green: 0.2, blue: 0.2), "inputColor1": CIColor(red: 0.8, green: 0.8, blue: 0.8),
        ])!.outputImage!
        let checker = CIFilter(name: "CICheckerboardGenerator", parameters: [
            "inputWidth": 1, "inputSharpness": 1,
            "inputColor0": CIColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 0.2),
            "inputColor1": CIColor(red: 0, green: 0, blue: 0, alpha: 0),
        ])!.outputImage!
        return checker.composited(over: gradient).cropped(to: extent)
    }

    private func pixels(_ image: CIImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: Int(extent.width * extent.height) * 4)
        CIContext().render(image, toBitmap: &bytes, rowBytes: Int(extent.width) * 4, bounds: extent,
                           format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        return bytes
    }

    private func render(amount: Double) throws -> [UInt8] {
        let descriptor = try #require(EffectRegistry.descriptor(id: "detail.enhance"))
        return pixels(descriptor.render(source(), effect: .make("detail.enhance", ["amount": amount]), atOffset: 0))
    }

    @Test func zeroAmountLeavesTheImageUntouched() throws {
        #expect(try render(amount: 0) == pixels(source()))
    }

    @Test func strongerAmountChangesMorePixels() throws {
        let original = pixels(source())
        func difference(_ rendered: [UInt8]) -> Int { zip(rendered, original).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) } }
        let light = difference(try render(amount: 0.3))
        let strong = difference(try render(amount: 1))
        #expect(light > 0)
        #expect(strong > light)
    }

    @Test func rendersBeforeTheIndividualDetailEffects() {
        let stack = [Effect.make("blur.sharpen"), Effect.make("detail.clarity")]
        #expect(EffectRegistry.insertIndex(stack, for: "detail.enhance") == 0)
    }
}
