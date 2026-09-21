import CryptoKit
import Foundation

struct EffectPackage: Decodable {
    struct Resource: Decodable {
        let path: String
        let sha256: String
    }

    let schema: String
    let id: String
    let name: String
    let renderer: String
    let resource: Resource
    let sequence: SequenceEffect?

    static func lutURL(in directory: URL) throws -> URL {
        try resourceURL(in: directory, renderer: "color.lut", filename: "look.cube")
    }

    static func sequenceURL(in directory: URL) throws -> (URL, SequenceEffect) {
        let url = try resourceURL(in: directory, renderer: "overlay.sequence", filename: "overlay.mov")
        let manifest = try JSONDecoder().decode(Self.self, from: Data(contentsOf: directory.appendingPathComponent("manifest.json")))
        guard let sequence = manifest.sequence else { throw LUTStoreError.invalid(directory.lastPathComponent) }
        return (url, sequence)
    }

    private static func resourceURL(in directory: URL, renderer: String, filename: String) throws -> URL {
        let manifest = try JSONDecoder().decode(Self.self, from: Data(contentsOf: directory.appendingPathComponent("manifest.json")))
        guard manifest.schema == "palmier.effect-package/v1", manifest.renderer == renderer,
              !manifest.id.isEmpty, !manifest.name.isEmpty,
              manifest.resource.path == filename else {
            throw LUTStoreError.invalid(directory.lastPathComponent)
        }
        let root = directory.resolvingSymlinksInPath().standardizedFileURL
        let lut = directory.appendingPathComponent(manifest.resource.path).resolvingSymlinksInPath().standardizedFileURL
        guard lut.deletingLastPathComponent() == root else {
            throw LUTStoreError.invalid(directory.lastPathComponent)
        }
        let data = try Data(contentsOf: lut)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == manifest.resource.sha256 else { throw LUTStoreError.invalid(directory.lastPathComponent) }
        return lut
    }
}
