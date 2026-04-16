import SwiftUI

/// Displays a single detected gesture event in the history list.
struct GestureEventRow: View {
    let gesture: DetectedGesture

    var body: some View {
        HStack(spacing: Spacing.md) {
            // Gesture icon
            Image(systemName: gesture.type.icon)
                .font(.system(size: 20))
                .foregroundStyle(Color.edgelessAccent)
                .frame(width: 36, height: 36)
                .background(Color.edgelessAccent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))

            // Gesture info
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(gesture.type.displayName)
                    .font(.edgelessBodyMedium)
                    .foregroundStyle(Color.edgelessTextPrimary)

                Text(gesture.timestamp, style: .time)
                    .font(.edgelessSmall)
                    .foregroundStyle(Color.edgelessTextTertiary)
            }

            Spacer()

            // Confidence badge
            Text("\(Int(gesture.confidence * 100))%")
                .font(.edgelessBadge)
                .foregroundStyle(confidenceColor)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(confidenceColor.opacity(0.12))
                .clipShape(Capsule())
        }
        .padding(.vertical, Spacing.xs)
    }

    private var confidenceColor: Color {
        if gesture.confidence > 0.8 { return .edgelessSage }
        if gesture.confidence > 0.6 { return .edgelessWarning }
        return .edgelessTextSecondary
    }
}
