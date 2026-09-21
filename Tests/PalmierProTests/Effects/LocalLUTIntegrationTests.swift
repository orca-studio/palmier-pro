import CoreImage
import Foundation
import Testing
@testable import PalmierPro

struct LocalLUTIntegrationTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PALMIER_TEST_LUT"] != nil))
    func localResourceRendersThroughRegisteredLUTEffect() throws {
        let resourceInput = try #require(ProcessInfo.processInfo.environment["PALMIER_TEST_LUT"])
        let path = resourceInput.hasSuffix(".palmierfx") ? try EffectPackage.lutURL(in: URL(fileURLWithPath: resourceInput)).path : resourceInput
        let lut = try #require(LUTLoader.load(path: path))
        #expect(lut.dimension == 16)
        _ = try #require(CIKernelLoader.kernel("LUTTetra", "lutTetra"))
        let effect = try #require(EffectRegistry.all.first { $0.id == "color.lut" })
        let extent = CGRect(x: 0, y: 0, width: 96, height: 64)
        let input = CIImage(color: CIColor(red: 0.9, green: 0.2, blue: 0.1)).cropped(to: extent)
        let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
        func pixels(_ image: CIImage) -> [Float] {
            var result = [Float](repeating: 0, count: 4)
            context.render(image, toBitmap: &result, rowBytes: 16,
                           bounds: CGRect(x: 10, y: 10, width: 1, height: 1), format: .RGBAf, colorSpace: nil)
            return result
        }
        let original = pixels(input)
        let zero = effect.apply(input, .init(values: ["intensity": 0], strings: ["path": path]), extent)
        let result = effect.apply(input, .init(values: ["intensity": 1], strings: ["path": path]), extent)
        let rgb = pixels(result)
        #expect(abs(pixels(zero)[0] - original[0]) < 0.001)
        #expect(abs(rgb[0] - rgb[1]) < 0.04)
        #expect(abs(rgb[1] - rgb[2]) < 0.04)
        #expect(abs(rgb[0] - original[0]) > 0.1)
        let output = URL(fileURLWithPath: path).deletingLastPathComponent()
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        try context.writePNGRepresentation(of: result, to: output.appendingPathComponent("palmier-render.png"), format: .RGBA8, colorSpace: space)
        if let framePath = ProcessInfo.processInfo.environment["PALMIER_TEST_LUT_FRAME"] {
            let frame = try #require(CIImage(contentsOf: URL(fileURLWithPath: framePath)))
            let filtered = effect.apply(frame, .init(values: ["intensity": 1], strings: ["path": path]), frame.extent)
            try context.writePNGRepresentation(of: filtered, to: output.appendingPathComponent("palmier-frame.png"), format: .RGBA8, colorSpace: space)
        }

    }
}
