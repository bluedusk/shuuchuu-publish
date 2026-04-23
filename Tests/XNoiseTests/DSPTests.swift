import XCTest
@testable import XNoise

final class DSPTests: XCTestCase {
    private let sampleRate: Double = 48000
    private let frames = 48000 // 1 second

    private func rms(_ buffer: [Float]) -> Float {
        let sumSquares = buffer.reduce(Float(0)) { $0 + $1 * $1 }
        return (sumSquares / Float(buffer.count)).squareRoot()
    }

    private func mean(_ buffer: [Float]) -> Float {
        buffer.reduce(0, +) / Float(buffer.count)
    }

    private func render<R: NoiseRenderer>(_ renderer: inout R) -> [Float] {
        var buffer = [Float](repeating: 0, count: frames)
        buffer.withUnsafeMutableBufferPointer { ptr in
            renderer.render(into: ptr.baseAddress!, frameCount: frames)
        }
        return buffer
    }

    func testWhiteNoiseRMSInRange() {
        var r = WhiteNoiseRenderer()
        let buf = render(&r)
        let value = rms(buf)
        XCTAssertGreaterThan(value, 0.45)
        XCTAssertLessThan(value, 0.70)
    }

    func testWhiteNoiseZeroMean() {
        var r = WhiteNoiseRenderer()
        let buf = render(&r)
        XCTAssertEqual(mean(buf), 0, accuracy: 0.05)
    }

    func testPinkNoiseInRange() {
        var r = PinkNoiseRenderer()
        let buf = render(&r)
        let peak = buf.map(abs).max() ?? 0
        XCTAssertLessThanOrEqual(peak, 1.01)
        XCTAssertGreaterThan(rms(buf), 0.05)
    }

    func testBrownNoiseBounded() {
        var r = BrownNoiseRenderer()
        let buf = render(&r)
        let peak = buf.map(abs).max() ?? 0
        XCTAssertLessThanOrEqual(peak, 1.01)
        XCTAssertGreaterThan(rms(buf), 0.05)
    }

    func testBrownHasLowerHighFrequencyEnergyThanWhite() {
        var white = WhiteNoiseRenderer()
        var brown = BrownNoiseRenderer()
        let w = render(&white)
        let b = render(&brown)
        XCTAssertGreaterThan(zeroCrossings(w), zeroCrossings(b) * 3)
    }

    private func zeroCrossings(_ buf: [Float]) -> Int {
        var count = 0
        for i in 1..<buf.count where (buf[i-1] < 0) != (buf[i] < 0) { count += 1 }
        return count
    }
}
