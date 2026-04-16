import AVFoundation
import SoundAnalysis
import Combine

/// Stage 2: ML-powered sound classification using Apple's SoundAnalysis framework.
/// Classifies transient sounds as clap, snap, or ambient noise.
final class SoundClassifierService: NSObject, ObservableObject {
    @Published var lastClassification: String = ""
    @Published var lastConfidence: Float = 0

    let soundClassified = PassthroughSubject<(label: String, confidence: Float), Never>()

    private var streamAnalyzer: SNAudioStreamAnalyzer?
    private var classifyRequest: SNClassifySoundRequest?
    private let analysisQueue = DispatchQueue(label: "com.edgeless.theclapper.analysis")

    // Sound labels we care about from the built-in classifier
    static let relevantSounds: Set<String> = [
        "applause", "clapping", "finger_snapping", "hands",
        "slap", "tap", "knock"
    ]

    func setup(format: AVAudioFormat) {
        streamAnalyzer = SNAudioStreamAnalyzer(format: format)

        do {
            let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
            request.windowDuration = CMTime(seconds: 1.0, preferredTimescale: 1000)
            request.overlapFactor = 0.5
            try streamAnalyzer?.add(request, withObserver: self)
            classifyRequest = request
        } catch {
            print("SoundClassifier: Failed to create request: \(error)")
        }
    }

    func analyze(buffer: AVAudioPCMBuffer, at time: AVAudioTime) {
        analysisQueue.async { [weak self] in
            self?.streamAnalyzer?.analyze(buffer, atAudioFramePosition: time.sampleTime)
        }
    }

    func reset() {
        if let request = classifyRequest {
            streamAnalyzer?.remove(request)
        }
        streamAnalyzer = nil
        classifyRequest = nil
    }
}

extension SoundClassifierService: SNResultsObserving {
    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let classificationResult = result as? SNClassificationResult else { return }

        // Find the highest-confidence relevant sound
        let relevant = classificationResult.classifications
            .filter { Self.relevantSounds.contains($0.identifier) }
            .max(by: { $0.confidence < $1.confidence })

        guard let best = relevant, best.confidence > 0.4 else { return }

        DispatchQueue.main.async {
            self.lastClassification = best.identifier
            self.lastConfidence = Float(best.confidence)
        }

        soundClassified.send((label: best.identifier, confidence: Float(best.confidence)))
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {
        print("SoundClassifier: Analysis failed: \(error.localizedDescription)")
    }

    func requestDidComplete(_ request: SNRequest) {
        print("SoundClassifier: Request completed")
    }
}
