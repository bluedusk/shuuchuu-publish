import Foundation

/// Green noise: white filtered through a band-pass centered at ~500 Hz.
struct GreenNoiseRenderer: NoiseRenderer {
    private var rng = XorShift32()
    private let a1: Float
    private let a2: Float
    private let b0: Float
    private let b2: Float
    private var x1: Float = 0
    private var x2: Float = 0
    private var y1: Float = 0
    private var y2: Float = 0

    init(sampleRate: Double = 48000, centerHz: Double = 500, q: Double = 0.7) {
        let omega = 2 * .pi * centerHz / sampleRate
        let alpha = sin(omega) / (2 * q)
        let cosw = cos(omega)

        let a0 = 1 + alpha
        self.a1 = Float(-2 * cosw / a0)
        self.a2 = Float((1 - alpha) / a0)
        self.b0 = Float(alpha / a0)
        self.b2 = Float(-alpha / a0)
    }

    mutating func render(into buffer: UnsafeMutablePointer<Float>, frameCount: Int) {
        for i in 0..<frameCount {
            let x0 = rng.nextFloat()
            let y0 = b0 * x0 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1
            x1 = x0
            y2 = y1
            y1 = y0
            buffer[i] = y0 * 0.5
        }
    }
}
