import Foundation

enum ActionType: String, CaseIterable, Codable, Identifiable {
    case startStopRecording = "start_stop_recording"
    case takePhoto = "take_photo"
    case toggleFlashlight = "toggle_flashlight"
    case startStopTimer = "start_stop_timer"
    case none = "none"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .startStopRecording: return "Start/Stop Recording"
        case .takePhoto: return "Take Photo"
        case .toggleFlashlight: return "Toggle Flashlight"
        case .startStopTimer: return "Start/Stop Timer"
        case .none: return "No Action"
        }
    }

    var icon: String {
        switch self {
        case .startStopRecording: return "video.fill"
        case .takePhoto: return "camera.fill"
        case .toggleFlashlight: return "flashlight.on.fill"
        case .startStopTimer: return "timer"
        case .none: return "nosign"
        }
    }
}

struct GestureActionMapping: Codable, Identifiable {
    var id: String { gesture.rawValue }
    let gesture: GestureType
    var action: ActionType

    static let defaults: [GestureActionMapping] = [
        GestureActionMapping(gesture: .singleClap, action: .none),
        GestureActionMapping(gesture: .doubleClap, action: .startStopRecording),
        GestureActionMapping(gesture: .tripleClap, action: .takePhoto),
        GestureActionMapping(gesture: .snap, action: .toggleFlashlight)
    ]
}
