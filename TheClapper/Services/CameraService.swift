import AVFoundation
import UIKit
import Combine

/// Manages camera capture session for video recording triggered by gestures.
final class CameraService: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var isSessionRunning = false
    @Published var didCapturePhoto = false

    let captureSession = AVCaptureSession()

    private var movieOutput = AVCaptureMovieFileOutput()
    private var photoOutput = AVCapturePhotoOutput()
    private var durationTimer: Timer?
    /// True when the current recording was started by a gesture → auto-trim the
    /// clap moments off the ends when it finishes.
    private var trimOnFinish = false

    override init() {
        super.init()
        setupSession()
    }

    private func setupSession() {
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
    }

    func startSession() {
        guard !captureSession.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.startRunning()
            DispatchQueue.main.async {
                self?.isSessionRunning = true
            }
        }
    }

    func stopSession() {
        guard captureSession.isRunning else { return }
        captureSession.stopRunning()
        DispatchQueue.main.async { self.isSessionRunning = false }
    }

    /// `gestureTriggered` = started by a clap → auto-trim the clap moments off the
    /// ends when it finishes. The manual record button passes false.
    func toggleRecording(gestureTriggered: Bool = false) {
        if isRecording {
            stopRecording()
        } else {
            startRecording(gestureTriggered: gestureTriggered)
        }
    }

    func startRecording(gestureTriggered: Bool = false) {
        guard !isRecording else { return }
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
        // Read the current VIDEO input + its position BEFORE removing anything.
        // (Old bug: position was read from inputs.first AFTER removal — that was the
        // audio input, position .unspecified -> it never actually flipped.)
        guard let currentVideoInput = captureSession.inputs
            .compactMap({ $0 as? AVCaptureDeviceInput })
            .first(where: { $0.device.hasMediaType(.video) }) else { return }

        let newPosition: AVCaptureDevice.Position =
            currentVideoInput.device.position == .front ? .back : .front

        guard let newDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition),
              let newInput = try? AVCaptureDeviceInput(device: newDevice) else { return }

        captureSession.beginConfiguration()
        captureSession.removeInput(currentVideoInput)
        if captureSession.canAddInput(newInput) {
            captureSession.addInput(newInput)
        } else {
            captureSession.addInput(currentVideoInput) // revert if the new device can't be added
        }
        captureSession.commitConfiguration()
    }

    // MARK: - Auto-trim (strip the clap moments that bracket a gesture recording)

    private func saveToLibrary(_ url: URL) {
        DispatchQueue.main.async {
            UISaveVideoAtPathToSavedPhotosAlbum(url.path, nil, nil, nil)
        }
    }

    /// Trims the ends off a gesture-triggered clip. Recording *starts* ~0.65s after
    /// the start-claps (so they're already gone), but *stops* ~0.65s after the
    /// stop-claps — so the stop clap sits near the tail. Trim a small head + a
    /// larger tail. Falls back to the raw clip if it's too short or export fails.
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
                self.saveToLibrary(export.status == .completed ? outURL : url)
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
            self.isRecording = false
        }

        if let error = error {
            print("CameraService: Recording error: \(error.localizedDescription)")
            return
        }

        if trimOnFinish {
            trimClapEndsAndSave(outputFileURL)   // strip the stop-clap moment off the tail
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

        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)

        DispatchQueue.main.async {
            self.didCapturePhoto = true
            // Reset flash after 0.5s
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.didCapturePhoto = false
            }
        }
    }
}
