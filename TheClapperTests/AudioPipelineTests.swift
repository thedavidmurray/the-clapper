import XCTest
import AVFoundation
import Combine
@testable import TheClapper

final class AudioPipelineTests: XCTestCase {
    private var cancellables = Set<AnyCancellable>()

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    private func buffer(frames: Int = 1024, pulseStart: Int = 0,
                        pulseFrames: Int = 48, amplitude: Float = 0.3) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        let samples = buffer.floatChannelData![0]
        for index in 0..<frames {
            samples[index] = index >= pulseStart && index < pulseStart + pulseFrames
                ? (index.isMultiple(of: 2) ? amplitude : -amplitude) : 0
        }
        return buffer
    }

    private func monitor() -> AudioMonitorService {
        let monitor = AudioMonitorService()
        // The ViewModel's default sensitivity (0.5), not a relaxed test threshold.
        monitor.onsetThreshold = 0.085
        monitor.minimumAmplitude = 0.046
        monitor.debounceInterval = 0.155
        return monitor
    }

    func testOneMillisecondPulseIsDetectedAcrossTapSizesAndWindowBoundaries() {
        for frames in [1024, 4096] {
            for start in [0, 72, 1000] {
                let monitor = monitor()
                var onsets = 0
                monitor.transientDetected.sink { _ in onsets += 1 }.store(in: &cancellables)
                monitor.processBufferExternal(buffer(frames: frames, pulseStart: start),
                                              time: AVAudioTime(sampleTime: 0, atRate: 48000))
                XCTAssertEqual(onsets, 1, "frames=\(frames), pulseStart=\(start)")
            }
        }
    }

    func testSilenceAndLowLevelNoiseDoNotEmitOnsets() {
        let monitor = monitor()
        var onsets = 0
        monitor.transientDetected.sink { _ in onsets += 1 }.store(in: &cancellables)
        for amplitude: Float in [0, 0.01] {
            monitor.processBufferExternal(buffer(pulseFrames: 1024, amplitude: amplitude),
                                          time: AVAudioTime(sampleTime: 0, atRate: 48000))
        }
        XCTAssertEqual(onsets, 0)
    }

    func testSustainedSignalAndImmediateRepeatDoNotDoubleTrigger() {
        let monitor = monitor()
        var onsets = 0
        monitor.transientDetected.sink { _ in onsets += 1 }.store(in: &cancellables)
        let signal = buffer(pulseFrames: 1024)
        for _ in 0..<4 {
            monitor.processBufferExternal(signal, time: AVAudioTime(sampleTime: 0, atRate: 48000))
        }
        XCTAssertEqual(onsets, 1)
    }

    func testStoppingClearsOnsetHistoryBeforeNextSession() {
        let monitor = monitor()
        var onsets = 0
        monitor.transientDetected.sink { _ in onsets += 1 }.store(in: &cancellables)
        monitor.processBufferExternal(buffer(), time: AVAudioTime(sampleTime: 0, atRate: 48000))
        monitor.stopListening()
        monitor.processBufferExternal(buffer(), time: AVAudioTime(sampleTime: 0, atRate: 48000))
        XCTAssertEqual(onsets, 2, "a new listening session must not inherit the previous debounce")
    }

    func testEmptyBufferDoesNotEmitOnset() {
        let monitor = monitor()
        var onsets = 0
        monitor.transientDetected.sink { _ in onsets += 1 }.store(in: &cancellables)
        let empty = buffer()
        empty.frameLength = 0
        monitor.processBufferExternal(empty, time: AVAudioTime(sampleTime: 0, atRate: 48000))
        XCTAssertEqual(onsets, 0)
    }

    @MainActor
    func testPCMThroughViewModelRecognizesClapAndStartsMappedTimer() {
        let defaults = UserDefaults.standard
        let savedMappings = defaults.object(forKey: "gesture_mappings")
        let savedSensitivity = defaults.object(forKey: "clapper_sensitivity")
        defer {
            defaults.set(savedMappings, forKey: "gesture_mappings")
            defaults.set(savedSensitivity, forKey: "clapper_sensitivity")
        }
        defaults.removeObject(forKey: "gesture_mappings")
        defaults.removeObject(forKey: "clapper_sensitivity")
        let model = ClapperViewModel()
        model.actionDispatcher.updateMapping(gesture: .singleClap, action: .startStopTimer)
        let fired = expectation(description: "PCM -> onset -> single clap -> running timer")
        model.actionDispatcher.$isTimerRunning.filter { $0 }.prefix(1)
            .sink { _ in fired.fulfill() }.store(in: &cancellables)
        model.audioMonitor.processBufferExternal(buffer(),
                                                time: AVAudioTime(sampleTime: 0, atRate: 48000))
        wait(for: [fired], timeout: 2)
        XCTAssertEqual(model.transientCount, 1)
        XCTAssertEqual(model.lastGesture?.type, .singleClap)
        XCTAssertTrue(model.actionDispatcher.isTimerRunning)
        print("CLAPPER_PIPELINE: PCM(48/1024 frames, amplitude=0.3) -> onset=\(model.transientCount) -> gesture=\(String(describing: model.lastGesture?.type)) -> timerRunning=\(model.actionDispatcher.isTimerRunning)")
        if let gesture = model.lastGesture { model.actionDispatcher.dispatch(gesture: gesture) }
        model.stopListening()
    }
}
