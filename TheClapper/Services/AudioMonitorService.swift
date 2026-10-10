import AVFoundation
import Accelerate
import Combine

/// Stage 1: Low-latency amplitude monitoring with onset detection.
/// Uses vDSP for vectorized audio processing. Measures onset energy in 2ms
/// windows so short claps are not averaged away by a much longer audio tap.
/// Delivery latency still depends on the audio engine's callback buffer size.
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
            // Set synchronously (callers are main-actor): the guard above must see
            // the new state immediately, or back-to-back auto-start triggers
            // (.task + scenePhase .active) both pass and leak a second live
            // engine with the mic held.
            isListening = true
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
        lastOnsetTime = 0
        // Synchronous for the same reason as startListening: a stop immediately
        // followed by a start (e.g. route-change restart) must see isListening
        // false, not the stale async-mirrored value.
        isListening = false
        currentRMS = 0
        currentPeak = 0
        waveformSamples = Array(repeating: 0, count: 64)
    }

    /// Returns the audio engine's input format for SoundAnalysis setup
    var inputFormat: AVAudioFormat? {
        audioEngine?.inputNode.inputFormat(forBus: 0)
    }

    private func processBuffer(_ buffer: AVAudioPCMBuffer, time _: AVAudioTime) {
        guard buffer.frameLength > 0, buffer.format.sampleRate > 0,
              let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = vDSP_Length(buffer.frameLength)

        // Vectorized RMS via Accelerate
        var rms: Float = 0
        vDSP_measqv(channelData, 1, &rms, frameLength)
        rms = sqrtf(rms)

        // Vectorized peak via Accelerate
        var peak: Float = 0
        vDSP_maxmgv(channelData, 1, &peak, frameLength)

        // Downsample buffer for waveform display (64 points)
        let samples = downsampleForWaveform(channelData, frameCount: Int(buffer.frameLength))

        DispatchQueue.main.async {
            self.currentRMS = rms
            self.currentPeak = peak
            self.waveformSamples = samples
        }

        // A clap's attack can occupy only ~1ms of a 21ms (or larger) tap.
        // Whole-buffer RMS dilutes that attack below the sensitivity threshold
        // even while the peak/waveform visibly spikes. Keep whole-buffer levels
        // for display, but detect against short-window RMS and its noise floor.
        let windowFrames = max(1, Int(buffer.format.sampleRate * 0.002))
        let now = Date().timeIntervalSince1970
        for start in stride(from: 0, to: Int(buffer.frameLength), by: windowFrames) {
            let count = min(windowFrames, Int(buffer.frameLength) - start)
            var windowRMS: Float = 0
            vDSP_measqv(channelData.advanced(by: start), 1, &windowRMS, vDSP_Length(count))
            windowRMS = sqrtf(windowRMS)
            let derivative = windowRMS - smoothedRMS
            smoothedRMS = smoothedRMS * (1 - smoothingFactor) + windowRMS * smoothingFactor

            if derivative > onsetThreshold
                && windowRMS > minimumAmplitude
                && (now - lastOnsetTime) > debounceInterval {
                lastOnsetTime = now
                transientDetected.send(TransientEvent(timestamp: Date(timeIntervalSince1970: now)))
            }
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
