import Foundation
@testable import YugiTokenBar

/// 시드 고정 RNG (SplitMix64)
struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

func tempDir() -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ytb-test-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}
