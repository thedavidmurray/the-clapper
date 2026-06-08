import SwiftUI

/// Animated waveform visualization that shows real audio data.
/// Displays a circular pulse indicator + bar waveform from live mic samples.
struct WaveformView: View {
    let amplitude: Float
    let waveformSamples: [Float]
    let isListening: Bool
    let isRecording: Bool

    var body: some View {
        VStack(spacing: Spacing.lg) {
            // Circular pulse indicator
            ZStack {
                if isListening {
                    Circle()
                        .stroke(ringColor.opacity(0.12), lineWidth: 2)
                        .scaleEffect(1.0 + CGFloat(amplitude) * 0.6)
                        .animation(.easeOut(duration: 0.1), value: amplitude)

                    Circle()
                        .stroke(ringColor.opacity(0.06), lineWidth: 1)
                        .scaleEffect(1.3 + CGFloat(amplitude) * 1.0)
                        .animation(.easeOut(duration: 0.15), value: amplitude)
                }

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [mainColor.opacity(0.3), mainColor.opacity(0.03)],
                            center: .center,
                            startRadius: 0,
                            endRadius: 60
                        )
                    )
                    .scaleEffect(isListening ? 1.0 + CGFloat(amplitude) * 0.4 : 0.7)
                    .animation(.easeOut(duration: 0.08), value: amplitude)

                Image(systemName: centerIcon)
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(mainColor)
            }
            .frame(width: 140, height: 140)

            // Bar waveform from real samples
            if isListening {
                WaveformBars(samples: waveformSamples, color: barColor)
                    .frame(height: 48)
                    .padding(.horizontal, Spacing.xl)
            }
        }
    }

    private var mainColor: Color {
        if isRecording { return .recordingRed }
        if isListening { return .audioIndigo }
        return .edgelessTextTertiary
    }

    private var ringColor: Color {
        if isRecording { return .recordingRed }
        return .audioIndigo
    }

    private var barColor: Color {
        if isRecording { return .recordingRed }
        return .audioIndigo
    }

    private var centerIcon: String {
        if isRecording { return "record.circle" }
        if isListening { return "waveform" }
        return "mic.slash"
    }
}

/// Real-time waveform bar visualization from audio samples.
struct WaveformBars: View {
    let samples: [Float]
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 2) {
                ForEach(0..<samples.count, id: \.self) { index in
                    let height = max(2, CGFloat(samples[index]) * geometry.size.height)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(color.opacity(0.4 + Double(samples[index]) * 0.6))
                        .frame(width: barWidth(in: geometry), height: height)
                        .animation(.easeOut(duration: 0.06), value: samples[index])
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private func barWidth(in geometry: GeometryProxy) -> CGFloat {
        let totalSpacing = CGFloat(max(0, samples.count - 1)) * 2
        return max(1.5, (geometry.size.width - totalSpacing) / CGFloat(samples.count))
    }
}
