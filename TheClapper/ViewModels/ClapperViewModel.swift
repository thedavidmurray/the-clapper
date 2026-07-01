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

        // The monitor installs its own tap that runs onset detection AND the DSP
        // clap/snap classifier off each buffer, then emits transient events.
        // No second tap / SoundAnalysis needed.
        guard audioMonitor.startListening() != nil else { return }
        transientCount = 0
    }

    func stopListening() {
        audioMonitor.stopListening()
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
