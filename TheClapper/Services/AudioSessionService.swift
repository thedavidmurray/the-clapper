import AVFoundation

/// Configures the shared audio session for simultaneous recording and monitoring.
struct AudioSessionService {
    /// Activate the session for recording. Call right before starting the engine.
    static func activate() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
        } catch {
            print("AudioSession: activate failed: \(error)")
        }
    }

    /// Deactivate the session and RELEASE the microphone. Call when listening stops.
    /// `.notifyOthersOnDeactivation` clears the "in use" indicator for other apps
    /// (iPhone Mirroring, etc.) so the mic is actually freed.
    static func deactivate() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("AudioSession: deactivate failed: \(error)")
        }
    }

    static func requestMicrophonePermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }
}
