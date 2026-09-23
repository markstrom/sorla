import Accelerate
import Foundation

public final class SpectrumAnalyzer {
    public static let frameCount = 1024
    static let lowestFrequency: Double = 90
    static let highestFrequency: Double = 7000
    static let floorDecibels: Float = -60
    static let ceilingDecibels: Float = -14
    static let tiltDecibelsPerOctave: Float = 3

    public let sampleRate: Double
    private let log2Count = vDSP_Length(10)
    private let setup: FFTSetup
    private let window: UnsafeMutablePointer<Float>
    private let windowed: UnsafeMutablePointer<Float>
    private let real: UnsafeMutablePointer<Float>
    private let imaginary: UnsafeMutablePointer<Float>
    private let power: UnsafeMutablePointer<Float>
    private let lowerBins: SIMD8<Int>
    private let upperBins: SIMD8<Int>
    private let offsetDecibels: SIMD8<Float>

    public init(sampleRate: Double) {
        let count = Self.frameCount
        let half = count / 2
        self.sampleRate = sampleRate
        setup = vDSP_create_fftsetup(log2Count, FFTRadix(kFFTRadix2))!
        window = .allocate(capacity: count)
        windowed = .allocate(capacity: count)
        real = .allocate(capacity: half)
        imaginary = .allocate(capacity: half)
        power = .allocate(capacity: half)
        vDSP_hann_window(window, vDSP_Length(count), Int32(vDSP_HANN_DENORM))

        var windowSum: Float = 0
        vDSP_sve(window, 1, &windowSum, vDSP_Length(count))

        let binWidth = sampleRate / Double(count)
        let ratio = pow(Self.highestFrequency / Self.lowestFrequency, 1.0 / 8)
        var lower = SIMD8<Int>(repeating: 0)
        var upper = SIMD8<Int>(repeating: -1)
        var offset = SIMD8<Float>(repeating: 0)
        for band in 0..<8 {
            let low = Self.lowestFrequency * pow(ratio, Double(band))
            let high = low * ratio
            let first = max(1, Int((low / binWidth).rounded(.up)))
            let last = min(half - 1, max(first, Int((high / binWidth).rounded(.up)) - 1))
            lower[band] = first
            upper[band] = last
            // Speech energy falls with frequency; a gentle tilt keeps the upper bands visible.
            let tilt = Self.tiltDecibelsPerOctave * Float(log2((low * high).squareRoot() / Self.lowestFrequency))
            // The zrip output of a Hann-windowed sine of amplitude A peaks at A * sum(window).
            offset[band] = tilt - 20 * log10(windowSum)
        }
        lowerBins = lower
        upperBins = upper
        offsetDecibels = offset
    }

    deinit {
        vDSP_destroy_fftsetup(setup)
        window.deallocate()
        windowed.deallocate()
        real.deallocate()
        imaginary.deallocate()
        power.deallocate()
    }

    public func analyze(_ samples: UnsafeBufferPointer<Float>) -> SIMD8<Float> {
        let count = Self.frameCount
        let half = count / 2
        guard let base = samples.baseAddress, !samples.isEmpty else { return SIMD8(repeating: 0) }

        let used = min(samples.count, count)
        vDSP_vmul(base + (samples.count - used), 1, window, 1, windowed, 1, vDSP_Length(used))
        if used < count {
            vDSP_vclr(windowed + used, 1, vDSP_Length(count - used))
        }

        var split = DSPSplitComplex(realp: real, imagp: imaginary)
        windowed.withMemoryRebound(to: DSPComplex.self, capacity: half) { complex in
            vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(half))
        }
        vDSP_fft_zrip(setup, &split, 1, log2Count, FFTDirection(kFFTDirection_Forward))
        vDSP_zvmags(&split, 1, power, 1, vDSP_Length(half))

        let range = Self.ceilingDecibels - Self.floorDecibels
        var result = SIMD8<Float>(repeating: 0)
        for band in 0..<8 where upperBins[band] >= lowerBins[band] {
            var peak: Float = 0
            vDSP_maxv(power + lowerBins[band], 1, &peak, vDSP_Length(upperBins[band] - lowerBins[band] + 1))
            guard peak > 0 else { continue }
            let decibels = 10 * log10(peak) + offsetDecibels[band]
            let normalized = (decibels - Self.floorDecibels) / range
            result[band] = normalized > 0 ? min(normalized, 1) : 0
        }
        return result
    }
}
