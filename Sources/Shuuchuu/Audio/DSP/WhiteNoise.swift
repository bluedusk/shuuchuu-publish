import Foundation

protocol NoiseRenderer {
    mutating func render(into buffer: UnsafeMutablePointer<Float>, frameCount: Int)
}

/// xorshift32 — faster + less-jittery than Float.random(in:)
struct XorShift32 {
    private var state: UInt32
    init(seed: UInt32 = UInt32.random(in: 1...UInt32.max)) {
        self.state = seed == 0 ? 1 : seed
    }
    mutating func nextFloat() -> Float {
        state ^= state << 13
        state ^= state >> 17
        state ^= state << 5
        return Float(Int32(bitPattern: state)) / Float(Int32.max)
    }
}

struct WhiteNoiseRenderer: NoiseRenderer {
    private var rng = XorShift32()

    mutating func render(into buffer: UnsafeMutablePointer<Float>, frameCount: Int) {
        for i in 0..<frameCount {
            buffer[i] = rng.nextFloat()
        }
    }
}
