import Accelerate

/// Which percussive sound an onset most resembles. Pure DSP — no ML, no FFT.
enum PercussiveSound: String {
    case clap
    case snap
    case unknown
}

/// Lightweight clap-vs-snap classifier computed directly off an onset's audio
/// window using Accelerate. Physics, not machine learning:
///   • a finger **snap** is a brief, bright, high-frequency click → high
///     zero-crossing rate + high high-frequency-energy ratio, usually quieter.
///   • a **clap** is two palms → fuller, lower-mid, louder → lower ZCR / HF ratio.
///
/// This replaces the flaky Apple `SoundAnalysis` classifier (which confused the
/// two and added ~500ms latency). It runs instantly on the same buffer the onset
/// detector already has.
///
/// Thresholds are conservative starting points and are meant to be tuned against
/// real on-device recordings (the Camera-tab debug readout surfaces the live
/// values). All the math is a couple of vectorized passes — no per-sample cost
/// beyond the zero-crossing count.
struct PercussiveClassifier {

    /// Zero-crossing rate (0…1) at/above which the onset leans "snap".
    var zcrSplit: Float = 0.14
    /// High-frequency energy ratio (first-difference energy / signal energy)
    /// at/above which the onset leans "snap". Can exceed 1 for very bright sounds.
    var hfRatioSplit: Float = 0.9

    struct Features {
        let rms: Float          // loudness of the onset window
        let zcr: Float          // zero-crossing rate, 0…1
        let hfRatio: Float      // high-frequency energy / total energy
        let sound: PercussiveSound
    }

    /// Classify an onset window. `samples` is mono float PCM at the input sample rate.
    func classify(_ samples: UnsafePointer<Float>, count: Int) -> Features {
        guard count > 8 else {
            return Features(rms: 0, zcr: 0, hfRatio: 0, sound: .unknown)
        }
        let n = vDSP_Length(count)

        // --- RMS energy (loudness) ---
        var meanSquare: Float = 0
        vDSP_measqv(samples, 1, &meanSquare, n)
        let rms = sqrtf(meanSquare)

        // --- Zero-crossing rate (cheap brightness proxy) ---
        var crossings = 0
        var prev = samples[0]
        for i in 1..<count {
            let s = samples[i]
            if (prev < 0) != (s < 0) { crossings += 1 }
            prev = s
        }
        let zcr = Float(crossings) / Float(count - 1)

        // --- High-frequency energy ratio via first difference ---
        // diff[i] = x[i+1] - x[i]  (a crude high-pass). Its energy relative to the
        // signal's energy rises with high-frequency content → snaps score higher.
        var diff = [Float](repeating: 0, count: count - 1)
        vDSP_vsub(samples, 1, samples.advanced(by: 1), 1, &diff, 1, vDSP_Length(count - 1))
        var diffMeanSquare: Float = 0
        vDSP_measqv(diff, 1, &diffMeanSquare, vDSP_Length(count - 1))
        let denom = meanSquare > 1e-9 ? meanSquare : 1e-9
        let hfRatio = diffMeanSquare / denom

        // --- Decision: bright on either measure → snap, else clap ---
        let looksBright = (zcr >= zcrSplit) || (hfRatio >= hfRatioSplit)
        let sound: PercussiveSound = looksBright ? .snap : .clap

        return Features(rms: rms, zcr: zcr, hfRatio: hfRatio, sound: sound)
    }
}
