import SwiftUI

/// Main home screen showing audio visualization, gesture detection status, and recent events.
struct HomeView: View {
    @ObservedObject var viewModel: ClapperViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("The Clapper")
                        .font(.edgelessTitle)
                        .foregroundStyle(Color.edgelessTextPrimary)

                    Text(statusText)
                        .font(.edgelessCaption)
                        .foregroundStyle(statusColor)
                }

                Spacer()

                NavigationLink(destination: SettingsView(viewModel: viewModel)) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.edgelessTextSecondary)
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.base)

            Spacer()

            // Waveform visualization
            WaveformView(
                amplitude: viewModel.currentAmplitude,
                waveformSamples: viewModel.waveformSamples,
                isListening: viewModel.isListening,
                isRecording: viewModel.isRecording
            )
            .padding(.bottom, Spacing.lg)

            // Last gesture indicator
            if let gesture = viewModel.lastGesture {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: gesture.type.icon)
                        .foregroundStyle(Color.edgelessAccent)
                    Text(gesture.type.displayName)
                        .font(.edgelessHeadline)
                        .foregroundStyle(Color.edgelessTextPrimary)
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.md)
                .background(Color.edgelessAccent.opacity(0.12))
                .clipShape(Capsule())
                .transition(.scale.combined(with: .opacity))
            }

            // Audio level bar
            AudioLevelBar(
                level: viewModel.currentAmplitude,
                isTransient: viewModel.currentAmplitude > AudioLevel.transientThreshold
            )
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.lg)

            // Classification label
            if !viewModel.lastClassification.isEmpty {
                Text(viewModel.lastClassification.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.edgelessSmall)
                    .foregroundStyle(Color.edgelessTextTertiary)
                    .padding(.top, Spacing.sm)
            }

            Spacer()

            // Listen button
            Button(action: { viewModel.toggleListening() }, label: {
                HStack(spacing: Spacing.md) {
                    Image(systemName: viewModel.isListening ? "mic.fill" : "mic.slash.fill")
                    Text(viewModel.isListening ? "Listening" : "Start Listening")
                        .font(.edgelessBodyMedium)
                }
                .foregroundStyle(viewModel.isListening ? Color.edgelessBackground : Color.edgelessTextPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(viewModel.isListening ? Color.edgelessAccent : Color.edgelessSurfaceLight)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            })
            .padding(.horizontal, Spacing.lg)

            // Recording duration
            if viewModel.isRecording {
                HStack(spacing: Spacing.sm) {
                    Circle()
                        .fill(Color.recordingRed)
                        .frame(width: 8, height: 8)

                    Text(formatDuration(viewModel.recordingDuration))
                        .font(.edgelessBadge)
                        .foregroundStyle(Color.recordingRed)
                }
                .padding(.top, Spacing.md)
            }

            // Stopwatch timer
            if viewModel.actionDispatcher.isTimerRunning {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "timer")
                        .foregroundStyle(Color.edgelessWarning)
                    Text(formatDuration(viewModel.actionDispatcher.timerElapsed))
                        .font(.edgelessBadge)
                        .foregroundStyle(Color.edgelessWarning)
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.md)
                .background(Color.edgelessWarning.opacity(0.12))
                .clipShape(Capsule())
                .padding(.top, Spacing.md)
            }

            // Recent gestures list
            if !viewModel.recentGestures.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Recent")
                        .font(.edgelessCaption)
                        .foregroundStyle(Color.edgelessTextTertiary)
                        .padding(.horizontal, Spacing.lg)

                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(viewModel.recentGestures.prefix(5)) { gesture in
                                GestureEventRow(gesture: gesture)
                                    .padding(.horizontal, Spacing.lg)

                                if gesture.id != viewModel.recentGestures.prefix(5).last?.id {
                                    Divider()
                                        .background(Color.edgelessSurface)
                                        .padding(.horizontal, Spacing.lg)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }
                .padding(.top, Spacing.lg)
            }

            Spacer().frame(height: Spacing.lg)
        }
        .background(Color.edgelessBackground)
    }

    private var statusText: String {
        if viewModel.isRecording { return "Recording" }
        if viewModel.isListening { return "Listening for gestures" }
        return "Tap to start listening"
    }

    private var statusColor: Color {
        if viewModel.isRecording { return .recordingRed }
        if viewModel.isListening { return .edgelessSage }
        return .edgelessTextTertiary
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let tenths = Int(duration * 10) % 10
        return String(format: "%02d:%02d.%d", minutes, seconds, tenths)
    }
}
