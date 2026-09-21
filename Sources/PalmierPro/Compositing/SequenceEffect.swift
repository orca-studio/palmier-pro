import Foundation

struct SequenceEffect: Codable, Sendable {
    let sourceFrames: Int
    let sourceFPS: Int
    let width: Int
    let height: Int
    let blendMode: BlendMode

    func clip(mediaRef: String, startFrame: Int, durationFrames: Int, fps: Int,
              speedControl: Double, intensity: Double) throws -> Clip {
        guard !mediaRef.isEmpty, startFrame >= 0, durationFrames > 0, fps > 0, fps <= 240,
              sourceFrames > 0, sourceFrames <= 100_000, sourceFPS > 0, sourceFPS <= 240,
              width > 0, height > 0, width <= 8192, height <= 8192,
              speedControl.isFinite, (0...1).contains(speedControl),
              intensity.isFinite, (0...1).contains(intensity),
              startFrame <= Int.max - durationFrames else {
            throw LUTStoreError.invalid("Invalid sequence effect parameters")
        }
        let speed = 0.5 + 1.5 * speedControl
        guard Double(durationFrames) / Double(fps) * speed <= Double(sourceFrames) / Double(sourceFPS) else {
            throw LUTStoreError.invalid("Sequence duration exceeds the captured cycle")
        }
        var clip = Clip(mediaRef: mediaRef, startFrame: startFrame, durationFrames: durationFrames)
        clip.speed = speed
        clip.opacity = intensity
        clip.volume = 0
        clip.blendMode = blendMode
        return clip
    }
}
