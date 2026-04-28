import Foundation

/// Paul Kellet's 5-pole pink noise filter (public domain).
/// Reference: http://www.firstpr.com.au/dsp/pink-noise/
struct PinkNoiseRenderer: NoiseRenderer {
    private var rng = XorShift32()
    private var b0: Float = 0
    private var b1: Float = 0
    private var b2: Float = 0
    private var b3: Float = 0
    private var b4: Float = 0
    private var b5: Float = 0
    private var b6: Float = 0

    mutating func render(into buffer: UnsafeMutablePointer<Float>, frameCount: Int) {
        for i in 0..<frameCount {
            let w = rng.nextFloat()
            b0 = 0.99886 * b0 + w * 0.0555179
            b1 = 0.99332 * b1 + w * 0.0750759
            b2 = 0.96900 * b2 + w * 0.1538520
            b3 = 0.86650 * b3 + w * 0.3104856
            b4 = 0.55000 * b4 + w * 0.5329522
            b5 = -0.7616 * b5 - w * 0.0168980
            let pink = b0 + b1 + b2 + b3 + b4 + b5 + b6 + w * 0.5362
            b6 = w * 0.115926
            buffer[i] = pink * 0.11
        }
    }
}
