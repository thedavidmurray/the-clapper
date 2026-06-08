import Foundation

enum GestureType: String, CaseIterable, Codable, Identifiable {
    case singleClap = "single_clap"
    case doubleClap = "double_clap"
    case tripleClap = "triple_clap"
    case snap = "snap"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .singleClap: return "Single Clap"
        case .doubleClap: return "Double Clap"
        case .tripleClap: return "Triple Clap"
        case .snap: return "Snap"
        }
    }

    var icon: String {
        switch self {
        case .singleClap: return "hand.raised"
        case .doubleClap: return "hands.clap"
        case .tripleClap: return "hands.sparkles"
        case .snap: return "hand.point.up.left"
        }
    }
}

struct DetectedGesture: Identifiable {
    let id = UUID()
    let type: GestureType
    let timestamp: Date
    let confidence: Float
}
