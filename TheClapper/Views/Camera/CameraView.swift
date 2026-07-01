import SwiftUI

/// Full-screen camera view with gesture overlay.
struct CameraView: View {
    @ObservedObject var viewModel: ClapperViewModel
    @Binding var selectedTab: Int

    var body: some View {
        ZStack {
            // Camera preview
            CameraPreviewView(session: viewModel.cameraService.captureSession)
                .ignoresSafeArea()

            // Top overlay - status
            VStack {
                HStack {
                    // Back button -> return to the Monitor tab
                    Button(action: { selectedTab = 0 }, label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(Spacing.md)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    })

                    Spacer()

                    // Recording indicator
                    if viewModel.isRecording {
                        HStack(spacing: Spacing.sm) {
                            Circle()
                                .fill(Color.recordingRed)
                                .frame(width: 10, height: 10)

                            Text(formatDuration(viewModel.recordingDuration))
                                .font(.edgelessBadge)
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, Spacing.base)
                        .padding(.vertical, Spacing.sm)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                    }

                    Spacer()

                    // Switch camera
                    Button(action: { viewModel.cameraService.switchCamera() }, label: {
                        Image(systemName: "camera.rotate")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(Spacing.md)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    })
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.sm)

                Spacer()

                // Bottom controls
                HStack(alignment: .center, spacing: Spacing.xxl) {
                    Spacer()

                    // Listening status
                    VStack(spacing: Spacing.xs) {
                        Image(systemName: viewModel.isListening ? "ear.fill" : "ear")
                            .font(.system(size: 24))
                            .foregroundStyle(viewModel.isListening ? Color.edgelessSage : .white.opacity(0.5))

                        Text(viewModel.isListening ? "Listening" : "Paused")
                            .font(.edgelessSmall)
                            .foregroundStyle(.white.opacity(0.7))

                        // Temporary diagnostic readout: live mic level + onset count.
                        // If level moves when you clap but onsets stay 0 -> threshold;
                        // if level is flat -> mic/engine; if onsets rise but no gesture
                        // fires -> recognizer/dispatch. Remove before App Store submit.
                        Text(String(format: "lvl %.2f · onsets %d", viewModel.currentAmplitude, viewModel.transientCount))
                            .font(.system(size: 9, weight: .regular, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .onTapGesture { viewModel.toggleListening() }

                    // Record button (manual)
                    Button(action: { viewModel.cameraService.toggleRecording() }, label: {
                        ZStack {
                            Circle()
                                .stroke(.white, lineWidth: 4)
                                .frame(width: 72, height: 72)

                            if viewModel.isRecording {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.recordingRed)
                                    .frame(width: 28, height: 28)
                            } else {
                                Circle()
                                    .fill(Color.recordingRed)
                                    .frame(width: 60, height: 60)
                            }
                        }
                    })

                    // Last gesture
                    VStack(spacing: Spacing.xs) {
                        if let gesture = viewModel.lastGesture {
                            Image(systemName: gesture.type.icon)
                                .font(.system(size: 24))
                                .foregroundStyle(Color.edgelessAccent)

                            Text(gesture.type.displayName)
                                .font(.edgelessSmall)
                                .foregroundStyle(.white.opacity(0.7))
                        } else {
                            Image(systemName: "hand.raised")
                                .font(.system(size: 24))
                                .foregroundStyle(.white.opacity(0.3))

                            Text("No gesture")
                                .font(.edgelessSmall)
                                .foregroundStyle(.white.opacity(0.3))
                        }
                    }

                    Spacer()
                }
                .padding(.bottom, Spacing.xxl)
            }

            // Photo capture flash
            if viewModel.cameraService.didCapturePhoto {
                Color.white.opacity(0.6)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
                    .animation(.easeOut(duration: 0.3), value: viewModel.cameraService.didCapturePhoto)
            }

            // Gesture flash overlay
            if let gesture = viewModel.lastGesture,
               Date().timeIntervalSince(gesture.timestamp) < 1.0 {
                Color.edgelessAccent.opacity(0.1)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .onAppear {
            viewModel.cameraService.startSession()
        }
        .onDisappear {
            viewModel.cameraService.stopSession()
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
