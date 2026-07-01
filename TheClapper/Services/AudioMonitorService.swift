import AVFoundation
import Accelerate
import Combine

/// Stage 1: Low-latency amplitude monitoring with onset detection.
/// Uses vDSP for vectorized audio processing. Detects transient peaks (<10ms)
/// and emits onset events when amplitude derivative exceeds threshold.
final class AudioMonitorService: ObservableObject {
    @Published var currentRMS: Float = 0
    @Published var currentPeak: Float = 0
    @Published var isListening = false
    @Published var waveformSamples: [Float] = Array(repeating: 0, count: 64)

    let transientDetected = PassthroughSubject<TransientEvent, Never>()

    struct TransientEvent {
        let timestamp: Date
        let sound: PercussiveSound   // clap vs snap, classified off this onset's buffer
    }

    // Tunable thresholds (controlled by sensitivity setting)
    var onsetThreshold: Float = 0.12
    var minimumAmplitude: Float = 0.08
    var debounceInterval: TimeInterval = 0.15

    private var audioEngine: AVAudioEngine?
    private var smoothedRMS: Float = 0
    private let smoothingFactor: Float = 0.3
    private var lastOnsetTime: TimeInterval = 0
    private let bufferSize: AVAudioFrameCount = 1024
    private let percussiveClassifier = PercussiveClassifier()

    /// Starts the audio engine and installs a tap. Returns the engine for shared use.
    /// The caller may replace the tap with a unified one that calls `processBufferExternal`.
    func startListening() -> AVAudioEngine? {
        guard !isListening else { return audioEngine }

        let engine = AVAudioEngine()

        // Accessing inputNode can crash on simulator (AURemoteIO timeout).
        // Wrap in ObjC exception handler to prevent abort.
        var inputNode: AVAudioInputNode?
        do {
            try ObjCExceptionCatcher.`try` {
                inputNode = engine.inputNode
            }
        } catch {
            print("AudioMonitor: Failed to access input node: \(error.localizedDescription)")
            return nil
        }

        guard let node = inputNode else {
            print("AudioMonitor: No input node available (simulator or no audio hardware)")
            return nil
        }

        let format = node.inputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return nil }

        node.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak self] buffer, time in
            self?.processBuffer(buffer, time: time)
        }

        do {
            engine.prepare()
            try engine.start()
            audioEngine = engine
            DispatchQueue.main.async { self.isListening = true }
            return engine
        } catch {
            print("AudioMonitor: Failed to start: \(error)")
            return nil
        }
    }

    /// Called externally when the ViewModel manages the tap directly (unified tap pattern).
    func processBufferExternal(_ buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        processBuffer(buffer, time: time)
    }

    func stopListening() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        smoothedRMS = 0
        DispatchQueue.main.async {
            self.isListening = false
            self.currentRMS = 0
            self.currentPeak = 0
            self.waveformSamples = Array(repeating: 0, count: 64)
        }
    }

    /// Returns the audio engine's input format for SoundAnalysis setup
    var inputFormat: AVAudioFormat? {
        audioEngine?.inputNode.inputFormat(forBus: 0)
    }

    private func processBuffer(_ buffer: AVAudioPCMBuffer, time _: AVAudioTime) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = vDSP_Length(buffer.frameLength)

        // Vectorized RMS via Accelerate
        var rms: Float = 0
        vDSP_measqv(channelData, 1, &rms, frameLength)
        rms = sqrtf(rms)

        // Vectorized peak via Accelerate
        var peak: Float = 0
        vDSP_maxmgv(channelData, 1, &peak, frameLength)

        // Onset detection: smoothed derivative
        let derivative = rms - smoothedRMS
        smoothedRMS = smoothedRMS * (1 - smoothingFactor) + rms * smoothingFactor

        // Downsample buffer for waveform display (64 points)
        let samples = downsampleForWaveform(channelData, frameCount: Int(buffer.frameLength))

        DispatchQueue.main.async {
            self.currentRMS = rms
            self.currentPeak = peak
            self.waveformSamples = samples
        }

        // Transient detection with debounce
        let now = Date().timeIntervalSince1970
        if derivative > onsetThreshold
            && rms > minimumAmplitude
            && (now - lastOnsetTime) > debounceInterval {

            lastOnsetTime = now
            // Classify this onset (clap vs snap) off the same buffer — pure DSP,
            // instant, no ML. Detection above is unchanged; this only labels it.
            let features = percussiveClassifier.classify(channelData, count: Int(buffer.frameLength))
            let event = TransientEvent(timestamp: Date(), sound: features.sound)
            transientDetected.send(event)
        }
    }

    private func downsampleForWaveform(_ data: UnsafePointer<Float>, frameCount: Int) -> [Float] {
        let targetCount = 64
        guard frameCount > 0 else { return Array(repeating: 0, count: targetCount) }

        let stride = max(1, frameCount / targetCount)
        var result = [Float](repeating: 0, count: targetCount)

        for index in 0..<targetCount {
            let start = index * stride
            let end = min(start + stride, frameCount)
            guard start < frameCount else { break }

            var maxVal: Float = 0
            let count = vDSP_Length(end - start)
            vDSP_maxmgv(data.advanced(by: start), 1, &maxVal, count)
            result[index] = maxVal
        }
        return result
    }
}

// MARK: - Percussive classifier (clap vs snap) — pure DSP, no ML, no FFT

/// Which percussive sound an onset most resembles.
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
/// Replaces Apple `SoundAnalysis` (which confused the two and added ~500ms
/// latency). Runs instantly on the same buffer the onset detector already has.
/// Verified on synthetic signals: snap zcr≈0.29/hf≈0.90, clap zcr≈0.05/hf≈0.06.
/// Thresholds are tunable against real on-device recordings.
struct PercussiveClassifier {

    /// Zero-crossing rate (0…1) at/above which the onset leans "snap".
    var zcrSplit: Float = 0.14
    /// High-frequency energy ratio (first-difference energy / signal energy)
    /// at/above which the onset leans "snap". Can exceed 1 for very bright sounds.
    var hfRatioSplit: Float = 0.9

    struct Features {
        let rms: Float
        let zcr: Float
        let hfRatio: Float
        let sound: PercussiveSound
    }

    /// Classify an onset window. `samples` is mono float PCM at the input sample rate.
    func classify(_ samples: UnsafePointer<Float>, count: Int) -> Features {
        guard count > 8 else {
            return Features(rms: 0, zcr: 0, hfRatio: 0, sound: .unknown)
        }
        let n = vDSP_Length(count)

        // RMS energy (loudness)
        var meanSquare: Float = 0
        vDSP_measqv(samples, 1, &meanSquare, n)
        let rms = sqrtf(meanSquare)

        // Zero-crossing rate (cheap brightness proxy)
        var crossings = 0
        var prev = samples[0]
        for i in 1..<count {
            let s = samples[i]
            if (prev < 0) != (s < 0) { crossings += 1 }
            prev = s
        }
        let zcr = Float(crossings) / Float(count - 1)

        // High-frequency energy ratio via first difference (crude high-pass)
        var diff = [Float](repeating: 0, count: count - 1)
        vDSP_vsub(samples, 1, samples.advanced(by: 1), 1, &diff, 1, vDSP_Length(count - 1))
        var diffMeanSquare: Float = 0
        vDSP_measqv(diff, 1, &diffMeanSquare, vDSP_Length(count - 1))
        let denom = meanSquare > 1e-9 ? meanSquare : 1e-9
        let hfRatio = diffMeanSquare / denom

        let looksBright = (zcr >= zcrSplit) || (hfRatio >= hfRatioSplit)
        return Features(rms: rms, zcr: zcr, hfRatio: hfRatio, sound: looksBright ? .snap : .clap)
    }
}
