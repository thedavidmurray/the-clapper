import UIKit

/// Provides haptic feedback for gesture detection and action execution.
struct HapticService {
    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private let notification = UINotificationFeedbackGenerator()

    func transientDetected() {
        lightImpact.impactOccurred()
    }

    func gestureConfirmed() {
        mediumImpact.impactOccurred()
    }

    func recordingStarted() {
        heavyImpact.impactOccurred()
    }

    func recordingStopped() {
        notification.notificationOccurred(.success)
    }

    func error() {
        notification.notificationOccurred(.error)
    }
}
