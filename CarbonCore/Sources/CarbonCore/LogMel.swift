import Accelerate
import Foundation

/// SpeechBrain's log-mel filterbank features, the input of the VoxLingua107 language classifier: 60 mel bands every
/// 10 ms of 16 kHz mono audio, from 25 ms periodic Hamming frames centred with zero padding, in dB floored 80 dB
/// under the loudest. A port of `frontend.py` in aufklarer/SpeechBrain-ECAPA-VoxLingua107-21M-CoreML; the model
/// itself subtracts the mean.
public enum LogMel {
    public static let sampleRate = 16_000.0
    public static let bands = 60
    static let fftLength = 400
    static let hop = 160
    static let bins = fftLength / 2 + 1
    static let topDB: Float = 80

    /// One row of `bands` values per 10 ms frame. Empty for no samples.
    public static func features(of samples: [Float]) -> [[Float]] {
        guard !samples.isEmpty else { return [] }
        let frames = 1 + samples.count / hop
        let padded = [Float](repeating: 0, count: fftLength / 2) + samples + [Float](repeating: 0, count: fftLength / 2)
        var windowed = [Float](repeating: 0, count: frames * fftLength)
        for frame in 0..<frames {
            let start = frame * hop
            vDSP_vmul(
                Array(padded[start..<start + fftLength]), 1, window, 1, &windowed[frame * fftLength], 1,
                vDSP_Length(fftLength))
        }
        let real = multiply(windowed, rows: frames, by: dftCosines, columns: bins, inner: fftLength)
        let imaginary = multiply(windowed, rows: frames, by: dftSines, columns: bins, inner: fftLength)
        let power = vDSP.add(vDSP.square(real), vDSP.square(imaginary))
        let mel = multiply(power, rows: frames, by: filterbank, columns: bands, inner: bins)
        let decibels = vDSP.multiply(10, vForce.log10(vDSP.clip(mel, to: 1e-10...Float.greatestFiniteMagnitude)))
        let floored = vDSP.clip(decibels, to: (vDSP.maximum(decibels) - topDB)...Float.greatestFiniteMagnitude)
        return (0..<frames).map { Array(floored[$0 * bands..<($0 + 1) * bands]) }
    }

    /// `a` (`rows` × `inner`) times `b` (`inner` × `columns`), row-major.
    private static func multiply(_ a: [Float], rows: Int, by b: [Float], columns: Int, inner: Int) -> [Float] {
        var product = [Float](repeating: 0, count: rows * columns)
        vDSP_mmul(a, 1, b, 1, &product, 1, vDSP_Length(rows), vDSP_Length(columns), vDSP_Length(inner))
        return product
    }

    private static let window: [Float] = (0..<fftLength).map {
        Float(0.54 - 0.46 * cos(2 * Double.pi * Double($0) / Double(fftLength)))
    }

    /// The real DFT as two `fftLength` × `bins` matrices: 400 is no length vDSP's FFTs take.
    private static let dftCosines = dft(cos)
    private static let dftSines = dft(sin)

    private static func dft(_ wave: (Double) -> Double) -> [Float] {
        (0..<fftLength).flatMap { sample in
            (0..<bins).map { bin in Float(wave(2 * Double.pi * Double(bin * sample % fftLength) / Double(fftLength))) }
        }
    }

    /// SpeechBrain's triangular filters, `bins` × `bands`: each triangle uses its lower-side width on both sides.
    private static let filterbank: [Float] = {
        func mel(_ hz: Double) -> Double { 2595 * log10(1 + hz / 700) }
        func hz(_ mel: Double) -> Double { 700 * (pow(10, mel / 2595) - 1) }
        let top = mel(sampleRate / 2)
        let points = (0..<bands + 2).map { hz(top * Double($0) / Double(bands + 1)) }
        return (0..<bins).flatMap { bin in
            let frequency = sampleRate / 2 * Double(bin) / Double(bins - 1)
            return (0..<bands).map { band in
                let slope = (frequency - points[band + 1]) / (points[band + 1] - points[band])
                return Float(max(0, min(slope + 1, 1 - slope)))
            }
        }
    }()
}
