import CryptoKit
import Foundation
import Testing
@testable import PalmierPro

struct EffectPackageTests {
    @Test func validatesContentAndRejectsTamperingAndTraversal() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".palmierfx")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let lut = root.appendingPathComponent("look.cube")
        let data = Data("LUT_3D_SIZE 2\n".utf8)
        try data.write(to: lut)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        func manifest(path: String = "look.cube", renderer: String = "color.lut") throws {
            let value: [String: Any] = ["schema": "palmier.effect-package/v1", "id": "test", "name": "test", "renderer": renderer,
                                       "resource": ["path": path, "sha256": hash]]
            try JSONSerialization.data(withJSONObject: value).write(to: root.appendingPathComponent("manifest.json"))
        }
        try manifest()
        #expect(try EffectPackage.lutURL(in: root) == lut.resolvingSymlinksInPath())
        try Data("changed".utf8).write(to: lut)
        #expect(throws: (any Error).self) { try EffectPackage.lutURL(in: root) }
        try data.write(to: lut)
        try manifest(path: "../look.cube")
        #expect(throws: (any Error).self) { try EffectPackage.lutURL(in: root) }
        try manifest(renderer: "native.lua")
        #expect(throws: (any Error).self) { try EffectPackage.lutURL(in: root) }
    }
}
