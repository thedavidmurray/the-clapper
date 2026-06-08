import UIKit

/// Provides haptic feedback for gesture detection and action execution.
struct HapticService {
    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)

    func transientDetected() {
        lightImpact.impactOccurred()
    }

    func gestureConfirmed() {
        mediumImpact.impactOccurred()
    }
}
