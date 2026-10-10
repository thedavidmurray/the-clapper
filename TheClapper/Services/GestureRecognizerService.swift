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

    // Onset timestamps for the sequence in progress; resolves by count
    // (single/double/triple clap). Snaps count as claps in v1 — distinguishing
    // them reliably across rooms/mics needs more work (see build-12 classifier
    // in git history for the starting point).
    private var onsetTimestamps: [Date] = []

    private var pendingTimer: Timer?

    // Timing thresholds (seconds). Inter-clap widened to 0.6 — 0.5 was too tight
    // for a natural double-clap, so the second clap fell outside the window.
    private let maxInterClapInterval: TimeInterval = 0.6
    private let patternWaitTime: TimeInterval = 0.65

    /// Called by Stage 1 when a transient onset is detected (<10ms latency).
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

    private func resolveSequence() {
        pendingTimer?.invalidate()
        pendingTimer = nil

        let count = onsetTimestamps.count
        let firstOnset = onsetTimestamps.first
        onsetTimestamps.removeAll()

        guard count > 0 else { return }

        let gestureType: GestureType
        switch count {
        case 1: gestureType = .singleClap
        case 2: gestureType = .doubleClap
        default: gestureType = .tripleClap
        }

        emitGesture(gestureType, confidence: 0.85, firstOnsetAt: firstOnset)
    }

    private func emitGesture(_ type: GestureType, confidence: Float, firstOnsetAt: Date?) {
        let gesture = DetectedGesture(type: type, timestamp: .now, confidence: confidence, firstOnsetAt: firstOnsetAt)

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
