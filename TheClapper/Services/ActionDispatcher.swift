import AVFoundation
import UIKit
import Combine

/// Dispatches actions based on recognized gestures and user-configured mappings.
final class ActionDispatcher: ObservableObject {
    @Published var mappings: [GestureActionMapping] = GestureActionMapping.defaults
    @Published var lastExecutedAction: ActionType?
    @Published var isTimerRunning = false
    @Published var timerElapsed: TimeInterval = 0

    private let cameraService: CameraService
    private let hapticService = HapticService()
    private var timer: Timer?

    init(cameraService: CameraService) {
        self.cameraService = cameraService
        loadMappings()
    }

    func dispatch(gesture: DetectedGesture) {
        guard let mapping = mappings.first(where: { $0.gesture == gesture.type }),
              mapping.action != .none else { return }

        hapticService.gestureConfirmed()

        switch mapping.action {
        case .startStopRecording:
            cameraService.toggleRecording()
        case .takePhoto:
            cameraService.capturePhoto()
        case .toggleFlashlight:
            toggleFlashlight()
        case .startStopTimer:
            toggleTimer()
        case .none:
            break
        }

        DispatchQueue.main.async {
            self.lastExecutedAction = mapping.action
        }
    }

    func updateMapping(gesture: GestureType, action: ActionType) {
        if let index = mappings.firstIndex(where: { $0.gesture == gesture }) {
            mappings[index] = GestureActionMapping(gesture: gesture, action: action)
            saveMappings()
        }
    }

    private func toggleTimer() {
        if isTimerRunning {
            timer?.invalidate()
            timer = nil
            isTimerRunning = false
        } else {
            timerElapsed = 0
            isTimerRunning = true
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self else { return }
                DispatchQueue.main.async {
                    self.timerElapsed += 0.1
                }
            }
        }
    }

    private func toggleFlashlight() {
        guard let device = AVCaptureDevice.default(for: .video),
              device.hasTorch else { return }

        do {
            try device.lockForConfiguration()
            device.torchMode = device.torchMode == .on ? .off : .on
            device.unlockForConfiguration()
        } catch {
            print("ActionDispatcher: Flashlight error: \(error)")
        }
    }

    private func saveMappings() {
        if let data = try? JSONEncoder().encode(mappings) {
            UserDefaults.standard.set(data, forKey: "gesture_mappings")
        }
    }

    private func loadMappings() {
        if let data = UserDefaults.standard.data(forKey: "gesture_mappings"),
           let saved = try? JSONDecoder().decode([GestureActionMapping].self, from: data) {
            mappings = saved
        }
    }
}
