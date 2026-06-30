import Foundation
import Combine

/// Combines both detection layers into gesture recognition.
/// Stage 1 (AudioMonitor transient) provides fast onset timestamps.
/// Stage 2 (SoundAnalysis classification) confirms the sound type.
/// Pattern detection tracks clap sequences for single/double/triple.
final class GestureRecognizerService: ObservableObject {
    @Published var lastGesture: DetectedGesture?
    @Published var recentGestures: [DetectedGesture] = []

    let gestureRecognized = PassthroughSubject<DetectedGesture, Never>()

    // Onset timestamps from Stage 1 (fast, ~10ms)
    private var onsetTimestamps: [Date] = []
    // Classification results from Stage 2 (slower, ~500ms)
    private var lastClassificationLabel: String = ""
    private var lastClassificationConfidence: Float = 0
    private var lastClassificationTime: Date = .distantPast

    private var pendingTimer: Timer?

    // Timing thresholds (seconds). Inter-clap widened to 0.6 — 0.5 was too tight
    // for a natural double-clap, so the second clap fell outside the window.
    private let maxInterClapInterval: TimeInterval = 0.6
    private let patternWaitTime: TimeInterval = 0.65

    // Labels that count as "clap-like" for confidence. v1 counts onsets for
    // single/double/triple and treats any sharp transient as a clap; Apple's
    // built-in classifier frequently mislabels claps as "finger_snapping", so we
    // accept it here too (purely to keep the confidence value reasonable).
    // Distinct clap-vs-snap detection returns in v2 via a custom CreateML model.
    private static let clapLabels: Set<String> = [
        "applause", "clapping", "hands", "slap", "tap", "knock", "finger_snapping"
    ]
    private static let snapLabels: Set<String> = [
        "finger_snapping"
    ]

    /// Called by Stage 1 when a transient onset is detected (<10ms latency)
    func onTransientDetected(at timestamp: Date) {
        // Check if this onset is part of an ongoing sequence
        if let lastOnset = onsetTimestamps.last {
            let interval = timestamp.timeIntervalSince(lastOnset)
            if interval > maxInterClapInterval {
                // Previous sequence timed out -- resolve it now, start new
                resolveSequence()
                onsetTimestamps = [timestamp]
            } else {
                onsetTimestamps.append(timestamp)
            }
        } else {
            onsetTimestamps = [timestamp]
        }

        // Reset the wait timer for more onsets in the pattern
        pendingTimer?.invalidate()
        pendingTimer = Timer.scheduledTimer(withTimeInterval: patternWaitTime, repeats: false) { [weak self] _ in
            self?.resolveSequence()
        }
    }

    /// Called by Stage 2 when SoundAnalysis classifies the audio
    func onSoundClassified(label: String, confidence: Float) {
        lastClassificationLabel = label
        lastClassificationConfidence = confidence
        lastClassificationTime = Date()

        // v1: do NOT emit a snap here. Apple's built-in classifier confuses claps
        // and finger-snaps, and emitting a snap immediately short-circuited the
        // multi-clap window — so double/triple claps never resolved. Onset count
        // in resolveSequence() is now the single source of truth; classification
        // only informs the confidence value. (Snap as a distinct gesture returns
        // in v2 with a custom CreateML sound model.)
    }

    private func resolveSequence() {
        pendingTimer?.invalidate()
        pendingTimer = nil

        let count = onsetTimestamps.count
        onsetTimestamps.removeAll()

        guard count > 0 else { return }

        // Determine confidence from most recent classification
        let confidence: Float
        let timeSinceClassification = Date().timeIntervalSince(lastClassificationTime)

        if timeSinceClassification < 2.0 && Self.clapLabels.contains(lastClassificationLabel) {
            // SoundAnalysis confirmed it was a clap-like sound
            confidence = lastClassificationConfidence
        } else {
            // No recent classification -- use onset-only confidence (lower)
            confidence = 0.5
        }

        let gestureType: GestureType
        switch count {
        case 1: gestureType = .singleClap
        case 2: gestureType = .doubleClap
        default: gestureType = .tripleClap
        }

        emitGesture(gestureType, confidence: confidence)
    }

    private func emitGesture(_ type: GestureType, confidence: Float) {
        let gesture = DetectedGesture(type: type, timestamp: .now, confidence: confidence)

        DispatchQueue.main.async {
            self.lastGesture = gesture
            self.recentGestures.insert(gesture, at: 0)
            if self.recentGestures.count > 20 {
                self.recentGestures.removeLast()
            }
        }

        gestureRecognized.send(gesture)
    }
}
