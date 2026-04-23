import Foundation

/// Synth fluorescent-light buzz: 60 Hz fundamental + 120/180 Hz harmonics with jitter.
struct FluorescentHumRenderer: NoiseRenderer {
    private var rng = XorShift32()
    private let sampleRate: Float
    private var phase60: Float = 0
    private var phase120: Float = 0
    private var phase180: Float = 0

    init(sampleRate: Double = 48000) {
        self.sampleRate = Float(sampleRate)
    }

    mutating func render(into buffer: UnsafeMutablePointer<Float>, frameCount: Int) {
        let tau: Float = 2 * .pi
        let inc60: Float = tau * 60 / sampleRate
        let inc120: Float = tau * 120 / sampleRate
        let inc180: Float = tau * 180 / sampleRate

        for i in 0..<frameCount {
            let jitter: Float = 0.05 * rng.nextFloat()
            let s = (0.60 * sin(phase60)
                  + 0.25 * sin(phase120)
                  + 0.10 * sin(phase180)) * (1 + jitter)
            buffer[i] = s * 0.75

            phase60 += inc60
            phase120 += inc120
            phase180 += inc180
            if phase60 > tau { phase60 -= tau }
            if phase120 > tau { phase120 -= tau }
            if phase180 > tau { phase180 -= tau }
        }
    }
}
