import SwiftUI
import AVFoundation
import Combine

/// Main view model orchestrating the audio detection pipeline.
///
/// Pipeline (all pure DSP — no ML):
///   Mic -> AudioMonitorService tap
///     -> amplitude onset detection (<10ms) + clap/snap classification off the
///        same buffer (PercussiveClassifier)
///     -> GestureRecognizerService (single/double/triple clap, or snap)
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
    @Published var hasMicPermission = false
    /// True once the user has explicitly denied the mic — the UI must offer a
    /// path to Settings instead of a dead Start button (Guideline 2.1).
    @Published var micPermissionDenied = false
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
    let gestureRecognizer = GestureRecognizerService()
    let cameraService = CameraService()
    lazy var actionDispatcher = ActionDispatcher(cameraService: cameraService)

    private var cancellables = Set<AnyCancellable>()
    private let haptics = HapticService()

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
                // Feed the onset + its DSP clap/snap label to the recognizer.
                self.gestureRecognizer.onTransientDetected(at: event.timestamp, sound: event.sound)
            }
            .store(in: &cancellables)

        // Audio-session interruptions (phone call, Siri, alarm) stop the engine
        // out from under us. Tear down cleanly so the UI never shows a dead
        // "Listening", and resume when the system says we can.
        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let self,
                      let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
                switch type {
                case .began:
                    if self.isListening { self.stopListening() }
                case .ended:
                    let optionsRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                    if AVAudioSession.InterruptionOptions(rawValue: optionsRaw).contains(.shouldResume) {
                        self.startListening()
                    }
                @unknown default:
                    break
                }
            }
            .store(in: &cancellables)

        // Route changes (headphones/AirPods in or out) and engine configuration
        // changes invalidate the running engine — restart it cleanly.
        NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let self, self.isListening,
                      let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                      let reason = AVAudioSession.RouteChangeReason(rawValue: raw),
                      reason == .oldDeviceUnavailable || reason == .newDeviceAvailable else { return }
                self.restartListening()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .AVAudioEngineConfigurationChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.isListening else { return }
                self.restartListening()
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

        // Re-publish nested-service changes so views observing only the view model
        // actually refresh: SettingsView reads dispatcher mappings, HomeView reads
        // the stopwatch, CameraView reads didCapturePhoto / permission / save-error
        // state. Without these forwards the child models update but the UI doesn't.
        actionDispatcher.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        cameraService.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    func requestPermissions() async {
        // Only request permission here. The audio session is activated in
        // startListening() and deactivated in stopListening(), so the mic is
        // never held while we're not actively listening.
        hasMicPermission = await AudioSessionService.requestMicrophonePermission()
        micPermissionDenied = !hasMicPermission
    }

    func startListening() {
        guard hasMicPermission, !isListening else { return }

        // Acquire the mic right before the engine starts.
        AudioSessionService.activate()

        // The monitor installs its own tap that runs onset detection AND the DSP
        // clap/snap classifier off each buffer, then emits transient events.
        // No second tap / SoundAnalysis needed.
        guard audioMonitor.startListening() != nil else {
            // Engine failed to start — release the session so the mic "in use"
            // indicator doesn't stay lit for a dead engine.
            AudioSessionService.deactivate()
            return
        }
        transientCount = 0
    }

    private func restartListening() {
        stopListening()
        startListening()
    }

    func stopListening() {
        audioMonitor.stopListening()
        // Release the microphone so the orange "in use" indicator clears.
        AudioSessionService.deactivate()
        currentAmplitude = 0
        waveformSamples = Array(repeating: 0, count: 64)
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
