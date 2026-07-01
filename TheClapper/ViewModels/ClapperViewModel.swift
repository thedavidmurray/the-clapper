import SwiftUI
import AVFoundation
import Combine

/// Main view model orchestrating the two-stage audio detection pipeline.
///
/// Pipeline:
///   Mic -> AVAudioEngine tap
///     -> Stage 1: AudioMonitorService (amplitude onset, <10ms)
///        -> if transient: feed to Stage 2
///     -> Stage 2: SoundClassifierService (ML classification, ~500ms)
///     -> GestureRecognizerService (pattern detection)
///     -> ActionDispatcher (execute mapped action)
@MainActor
final class ClapperViewModel: ObservableObject {
    // State
    @Published var isListening = false
    @Published var isRecording = false
    @Published var currentAmplitude: Float = 0
    @Published var waveformSamples: [Float] = Array(repeating: 0, count: 64)
    @Published var lastGesture: DetectedGesture?
    @Published var recentGestures: [DetectedGesture] = []
    @Published var lastClassification: String = ""
    @Published var hasMicPermission = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var transientCount: Int = 0

    // Sensitivity (0.0 = least sensitive, 1.0 = most sensitive)
    @Published var sensitivity: Float = 0.5 {
        didSet { applySensitivity() }
    }

    /// When OFF (default), the mic is released the moment the app leaves the
    /// foreground. When ON, listening continues in the background (extra battery,
    /// mic stays active). Surfaced as a Settings toggle with an explanation.
    @Published var backgroundListeningEnabled: Bool = false {
        didSet { UserDefaults.standard.set(backgroundListeningEnabled, forKey: "clapper_background_listening") }
    }

    // Services
    let audioMonitor = AudioMonitorService()
    let soundClassifier = SoundClassifierService()
    let gestureRecognizer = GestureRecognizerService()
    let cameraService = CameraService()
    lazy var actionDispatcher = ActionDispatcher(cameraService: cameraService)

    private var cancellables = Set<AnyCancellable>()
    private let haptics = HapticService()

    // Transient gating: only feed SoundAnalysis when a transient is detected
    // Uses atomic-style access since it's read from the audio thread
    private let classifierGate = ClassifierGate()

    init() {
        loadSensitivity()
        backgroundListeningEnabled = UserDefaults.standard.bool(forKey: "clapper_background_listening")
        applySensitivity()
        setupBindings()
    }

    private func setupBindings() {
        // Stage 1: Transient onset -> feed classifier + gesture recognizer
        audioMonitor.transientDetected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self else { return }
                self.transientCount += 1
                self.haptics.transientDetected()

                // Gate: allow SoundAnalysis for next 1.5s after transient
                self.classifierGate.open(for: 1.5)

                // Feed onset to gesture recognizer (fast path)
                self.gestureRecognizer.onTransientDetected(at: event.timestamp)
            }
            .store(in: &cancellables)

        // Stage 2: SoundAnalysis classification -> gesture recognizer
        soundClassifier.soundClassified
            .receive(on: DispatchQueue.main)
            .sink { [weak self] result in
                self?.lastClassification = result.label
                self?.gestureRecognizer.onSoundClassified(
                    label: result.label,
                    confidence: result.confidence
                )
            }
            .store(in: &cancellables)

        // Gesture recognized -> Action dispatcher
        gestureRecognizer.gestureRecognized
            .receive(on: DispatchQueue.main)
            .sink { [weak self] gesture in
                guard let self else { return }
                self.lastGesture = gesture
                self.recentGestures = self.gestureRecognizer.recentGestures
                self.haptics.gestureConfirmed()
                self.actionDispatcher.dispatch(gesture: gesture)
            }
            .store(in: &cancellables)

        // Audio monitor level updates -> waveform
        audioMonitor.$currentPeak
            .receive(on: DispatchQueue.main)
            .assign(to: &$currentAmplitude)

        audioMonitor.$waveformSamples
            .receive(on: DispatchQueue.main)
            .assign(to: &$waveformSamples)

        audioMonitor.$isListening
            .receive(on: DispatchQueue.main)
            .assign(to: &$isListening)

        // Camera recording state
        cameraService.$isRecording
            .receive(on: DispatchQueue.main)
            .assign(to: &$isRecording)

        cameraService.$recordingDuration
            .receive(on: DispatchQueue.main)
            .assign(to: &$recordingDuration)

        // Re-publish mapping changes from the nested ActionDispatcher so views
        // observing the view model (SettingsView) actually refresh when the user
        // picks a new action. Without this the model updated but the UI showed the
        // old value — i.e. "the dropdown won't change". Only $mappings is forwarded
        // (not the dispatcher's timer ticks), so it stays cheap.
        actionDispatcher.$mappings
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    func requestPermissions() async {
        // Only request permission here. The audio session is activated in
        // startListening() and deactivated in stopListening(), so the mic is
        // never held while we're not actively listening.
        hasMicPermission = await AudioSessionService.requestMicrophonePermission()
    }

    func startListening() {
        guard hasMicPermission, !isListening else { return }

        // Acquire the mic right before the engine starts.
        AudioSessionService.activate()

        guard let engine = audioMonitor.startListening(),
              let format = audioMonitor.inputFormat else { return }

        // Setup SoundAnalysis on the same engine
        soundClassifier.setup(format: format)

        // Install a second tap is not possible on the same node,
        // so we add SoundAnalysis feeding inside the monitor's existing tap.
        // Instead, we'll observe buffers via the engine's input node directly.
        // The AudioMonitorService already has the tap, so we piggyback
        // by subscribing to transient events and feeding the classifier
        // from a separate tap -- but AVAudioEngine only allows ONE tap per node.
        //
        // Solution: Remove the monitor's tap and install our own unified tap.
        engine.inputNode.removeTap(onBus: 0)

        let inputFormat = engine.inputNode.inputFormat(forBus: 0)
        engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, time in
            guard let self else { return }

            // Stage 1: Fast amplitude analysis (always runs)
            self.audioMonitor.processBufferExternal(buffer, time: time)

            // Stage 2: Feed SoundAnalysis only when gated (transient detected recently)
            if self.classifierGate.isOpen {
                self.soundClassifier.analyze(buffer: buffer, at: time)
            }
        }

        // Engine is already started by audioMonitor, we just replaced the tap
        transientCount = 0
    }

    func stopListening() {
        audioMonitor.stopListening()
        soundClassifier.reset()
        // Release the microphone so the orange "in use" indicator clears.
        AudioSessionService.deactivate()
        currentAmplitude = 0
        waveformSamples = Array(repeating: 0, count: 64)
        lastClassification = ""
    }

    /// Called when the app enters the background. By default we stop listening
    /// (releasing the mic); if Background Listening is enabled we keep going.
    func handleEnteredBackground() {
        if !backgroundListeningEnabled && isListening {
            stopListening()
        }
    }

    func toggleListening() {
        if isListening {
            stopListening()
        } else {
            startListening()
        }
    }

    // MARK: - Sensitivity

    private func applySensitivity() {
        // Map 0.0-1.0 sensitivity to threshold values (inverse relationship)
        // High sensitivity = low thresholds
        // More sensitive ranges so real claps reliably trigger onsets on-device.
        audioMonitor.onsetThreshold = lerp(from: 0.15, to: 0.02, fraction: sensitivity)
        audioMonitor.minimumAmplitude = lerp(from: 0.08, to: 0.012, fraction: sensitivity)
        audioMonitor.debounceInterval = TimeInterval(lerp(from: 0.22, to: 0.09, fraction: sensitivity))
        saveSensitivity()
    }

    private func lerp(from start: Float, to end: Float, fraction: Float) -> Float {
        start + (end - start) * fraction
    }

    private func saveSensitivity() {
        UserDefaults.standard.set(sensitivity, forKey: "clapper_sensitivity")
    }

    private func loadSensitivity() {
        let saved = UserDefaults.standard.float(forKey: "clapper_sensitivity")
        if saved > 0 {
            sensitivity = saved
        }
    }
}

/// Thread-safe gate that opens for a duration then closes.
/// Read from the audio thread, written from main thread.
final class ClassifierGate: @unchecked Sendable {
    private var closeTime: TimeInterval = 0

    var isOpen: Bool {
        Date().timeIntervalSince1970 < closeTime
    }

    func open(for duration: TimeInterval) {
        closeTime = Date().timeIntervalSince1970 + duration
    }
}
