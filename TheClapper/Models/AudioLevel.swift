import Foundation

struct AudioLevel {
    let rms: Float
    let peak: Float
    let timestamp: Date

    var isTransient: Bool {
        peak > AudioLevel.transientThreshold
    }

    static let transientThreshold: Float = 0.3
    static let silenceThreshold: Float = 0.01
}
