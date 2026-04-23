import Foundation

/// Brown (red) noise: integrated white with leaky feedback.
struct BrownNoiseRenderer: NoiseRenderer {
    private var rng = XorShift32()
    private var lastOut: Float = 0

    mutating func render(into buffer: UnsafeMutablePointer<Float>, frameCount: Int) {
        for i in 0..<frameCount {
            let w = rng.nextFloat()
            lastOut = 0.98 * lastOut + 0.02 * w
            buffer[i] = lastOut * 2.0
        }
    }
}
