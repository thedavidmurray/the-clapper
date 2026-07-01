import AVFoundation
import UIKit
import Combine

/// Manages camera capture session for video recording triggered by gestures.
final class CameraService: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var isSessionRunning = false
    @Published var didCapturePhoto = false
    @Published var cameraPermissionDenied = false
    /// Set when a recording or Photos save fails, so the UI can tell the user
    /// instead of silently losing their clip.
    @Published var saveErrorMessage: String?

    let captureSession = AVCaptureSession()

    private var movieOutput = AVCaptureMovieFileOutput()
    private var photoOutput = AVCapturePhotoOutput()
    private var durationTimer: Timer?
    /// True when the current recording was started by a gesture → auto-trim the
    /// clap moments off the ends when it finishes.
    private var trimOnFinish = false
    /// Seconds of tail to cut when the recording was STOPPED by a gesture —
    /// measured from the gesture's first clap, so the entire stop gesture (both
    /// claps) is trimmed out, not just the last one.
    private var pendingStopTail: TimeInterval?
    /// True once inputs/outputs are configured (requires camera permission).
    private var isConfigured = false
    /// Serializes configure/start/stop/switch so fast tab switches can't race
    /// (async startRunning landing after a stopSession left the camera on).
    private let sessionQueue = DispatchQueue(label: "com.edgeless.theclapper.camera-session")

    override init() {
        super.init()
        sweepStaleTempFiles()
        // Session setup is deferred to the first Camera-tab visit so the camera
        // permission prompt appears in context, not at app launch.
    }

    private func setupSession() {
        guard !isConfigured else { return }
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .high

        // Video input
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let videoInput = try? AVCaptureDeviceInput(device: videoDevice),
              captureSession.canAddInput(videoInput) else {
            captureSession.commitConfiguration()
            return
        }
        captureSession.addInput(videoInput)

        // Audio input (separate from detection mic)
        if let audioDevice = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
           captureSession.canAddInput(audioInput) {
            captureSession.addInput(audioInput)
        }

        // Movie output
        if captureSession.canAddOutput(movieOutput) {
            captureSession.addOutput(movieOutput)
        }

        // Photo output
        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
        }

        captureSession.commitConfiguration()
        isConfigured = true
    }

    /// Checks camera authorization (requesting it in context on first use), then
    /// configures and starts the session on the serial session queue.
    func startSession() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startConfiguredSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                DispatchQueue.main.async { self.cameraPermissionDenied = !granted }
                if granted { self.startConfiguredSession() }
            }
        default:
            DispatchQueue.main.async { self.cameraPermissionDenied = true }
        }
    }

    private func startConfiguredSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.setupSession()
            guard self.isConfigured, !self.captureSession.isRunning else { return }
            self.captureSession.startRunning()
            DispatchQueue.main.async { self.isSessionRunning = true }
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self, self.captureSession.isRunning else { return }
            self.captureSession.stopRunning()
            DispatchQueue.main.async { self.isSessionRunning = false }
        }
    }

    /// `gestureTriggered` = invoked by a clap. When starting, that arms head-trim;
    /// when stopping, `gestureSpan` (time since the stop gesture's FIRST clap) sets
    /// how much tail to cut so the whole gesture — both claps — leaves the video.
    /// The manual record button passes neither.
    func toggleRecording(gestureTriggered: Bool = false, gestureSpan: TimeInterval? = nil) {
        if isRecording {
            pendingStopTail = gestureTriggered ? gestureSpan : nil
            stopRecording()
        } else {
            startRecording(gestureTriggered: gestureTriggered)
        }
    }

    func startRecording(gestureTriggered: Bool = false) {
        guard !isRecording else { return }
        // Never start recording without a running session and an active video
        // connection — AVCaptureMovieFileOutput.startRecording raises an ObjC
        // NSInvalidArgumentException otherwise (reachable by a clap mapped to
        // record while the user is on the Monitor tab, or with camera denied).
        guard captureSession.isRunning,
              let connection = movieOutput.connection(with: .video),
              connection.isActive else { return }
        trimOnFinish = gestureTriggered

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("clapper_\(Date().timeIntervalSince1970)")
            .appendingPathExtension("mov")

        movieOutput.startRecording(to: outputURL, recordingDelegate: self)

        DispatchQueue.main.async {
            self.isRecording = true
            self.recordingDuration = 0
        }

        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.recordingDuration += 0.1
            }
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        movieOutput.stopRecording()
        durationTimer?.invalidate()
        durationTimer = nil
    }

    func capturePhoto() {
        guard isSessionRunning else { return }
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func switchCamera() {
        guard !isRecording else { return }  // flipping mid-record kills the clip
        sessionQueue.async { [weak self] in
            guard let self else { return }
            // Read the current VIDEO input + its position BEFORE removing anything.
            // (Old bug: position was read from inputs.first AFTER removal — that was
            // the audio input, position .unspecified -> it never actually flipped.)
            guard let currentVideoInput = self.captureSession.inputs
                .compactMap({ $0 as? AVCaptureDeviceInput })
                .first(where: { $0.device.hasMediaType(.video) }) else { return }

            let newPosition: AVCaptureDevice.Position =
                currentVideoInput.device.position == .front ? .back : .front

            guard let newDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition),
                  let newInput = try? AVCaptureDeviceInput(device: newDevice) else { return }

            self.captureSession.beginConfiguration()
            self.captureSession.removeInput(currentVideoInput)
            if self.captureSession.canAddInput(newInput) {
                self.captureSession.addInput(newInput)
            } else {
                self.captureSession.addInput(currentVideoInput) // revert if the new device can't be added
            }
            self.captureSession.commitConfiguration()
        }
    }

    // MARK: - Saving (with completion so failures aren't silently lost)

    private func saveToLibrary(_ url: URL) {
        DispatchQueue.main.async {
            UISaveVideoAtPathToSavedPhotosAlbum(
                url.path,
                self,
                #selector(self.video(_:didFinishSavingWithError:contextInfo:)),
                nil
            )
        }
    }

    @objc private func video(_ videoPath: String, didFinishSavingWithError error: Error?, contextInfo: UnsafeMutableRawPointer?) {
        if let error {
            print("CameraService: Photos video save failed: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.saveErrorMessage = "Couldn't save the video to Photos. Check Photos access in Settings."
            }
        } else {
            // Saved to Photos — the temp copy is no longer needed.
            try? FileManager.default.removeItem(atPath: videoPath)
        }
    }

    @objc private func image(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeMutableRawPointer?) {
        if let error {
            print("CameraService: Photos image save failed: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.saveErrorMessage = "Couldn't save the photo to Photos. Check Photos access in Settings."
            }
        }
    }

    /// Removes leftover clapper_*.mov temp files from previous runs so the temp
    /// directory doesn't grow with every gesture recording.
    private func sweepStaleTempFiles() {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: fm.temporaryDirectory, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.lastPathComponent.hasPrefix("clapper_") && file.pathExtension == "mov" {
            try? fm.removeItem(at: file)
        }
    }

    // MARK: - Auto-trim (strip the clap moments that bracket a gesture recording)

    /// Trims the ends off a gesture-triggered clip. Recording *starts* ~0.65s after
    /// the start-claps (so they're already gone); the tail is computed from the
    /// stop gesture's first clap so the whole gesture is removed. Falls back to
    /// the raw clip if it's too short or export fails.
    private func trimClapEndsAndSave(_ url: URL, head: Double = 0.15, tail: Double = 0.9) {
        Task {
            let asset = AVURLAsset(url: url)
            let duration = (try? await asset.load(.duration)) ?? .zero
            let seconds = duration.seconds
            guard seconds.isFinite, seconds > head + tail + 0.5 else {
                self.saveToLibrary(url); return
            }
            let range = CMTimeRange(
                start: CMTime(seconds: head, preferredTimescale: 600),
                end: CMTime(seconds: seconds - tail, preferredTimescale: 600)
            )
            let outURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("clapper_trim_\(Int(Date().timeIntervalSince1970))")
                .appendingPathExtension("mov")
            guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
                self.saveToLibrary(url); return
            }
            export.outputURL = outURL
            export.outputFileType = .mov
            export.timeRange = range
            export.exportAsynchronously { [weak self] in
                guard let self else { return }
                if export.status == .completed {
                    try? FileManager.default.removeItem(at: url)  // raw original superseded
                    self.saveToLibrary(outURL)
                } else {
                    self.saveToLibrary(url)  // trim failed — keep the raw clip
                }
            }
        }
    }
}

extension CameraService: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        DispatchQueue.main.async {
            // Invalidate unconditionally: recordings that end abnormally
            // (error, backgrounding, disk full) must not leave the repeating
            // timer running with a climbing duration.
            self.durationTimer?.invalidate()
            self.durationTimer = nil
            self.isRecording = false
        }

        // Disk-full / interruption stops often return an error but a fully
        // playable file (AVErrorRecordingSuccessfullyFinishedKey) — keep those.
        let finishedOK = error == nil ||
            ((error! as NSError).userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool ?? false)
        guard finishedOK else {
            print("CameraService: Recording error: \(error!.localizedDescription)")
            DispatchQueue.main.async {
                self.saveErrorMessage = "The recording failed and couldn't be saved."
            }
            try? FileManager.default.removeItem(at: outputFileURL)
            return
        }

        // Tail: cut back past the ENTIRE stop gesture (first clap → recording end,
        // plus a small pad for the clap's attack and stop latency). Head: small
        // safety cut when the recording was gesture-started.
        let stopTail = pendingStopTail.map { $0 + 0.35 }
        pendingStopTail = nil
        if trimOnFinish || stopTail != nil {
            trimClapEndsAndSave(
                outputFileURL,
                head: trimOnFinish ? 0.15 : 0,
                tail: stopTail ?? 0.9
            )
        } else {
            saveToLibrary(outputFileURL)
        }
    }
}

extension CameraService: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            print("CameraService: Photo capture error: \(error.localizedDescription)")
            return
        }

        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else { return }

        DispatchQueue.main.async {
            // UIKit save call belongs on the main thread (the delegate fires on a
            // background queue); completion selector surfaces denied/failed saves.
            UIImageWriteToSavedPhotosAlbum(
                image,
                self,
                #selector(self.image(_:didFinishSavingWithError:contextInfo:)),
                nil
            )
            self.didCapturePhoto = true
            // Reset flash after 0.5s
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.didCapturePhoto = false
            }
        }
    }
}
