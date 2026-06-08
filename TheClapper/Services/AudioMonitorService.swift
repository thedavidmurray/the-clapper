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
            let event = TransientEvent(timestamp: Date())
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
