import Foundation

// v1 gestures are clap-count only. Snaps register as claps — reliably telling
// them apart across rooms/mics/distances needs more signal work (a
// self-calibrating DSP classifier lives in git history at build 12 as the
// starting point for a future refinement).
enum GestureType: String, CaseIterable, Codable, Identifiable {
    case singleClap = "single_clap"
    case doubleClap = "double_clap"
    case tripleClap = "triple_clap"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .singleClap: return "Single Clap"
        case .doubleClap: return "Double Clap"
        case .tripleClap: return "Triple Clap"
        }
    }

    var icon: String {
        switch self {
        case .singleClap: return "hand.raised"
        case .doubleClap: return "hands.clap"
        case .tripleClap: return "hands.sparkles"
        }
    }
}

struct DetectedGesture: Identifiable {
    let id = UUID()
    let type: GestureType
    let timestamp: Date
    let confidence: Float
    /// When the FIRST onset of this gesture's sequence occurred. Lets consumers
    /// trim media back past the whole gesture — e.g. cutting BOTH stop-claps out
    /// of a recording, not just the last one.
    var firstOnsetAt: Date?
}
