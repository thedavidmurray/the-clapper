import SwiftUI

/// Real-time audio level visualization bar.
struct AudioLevelBar: View {
    let level: Float
    let isTransient: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: Radius.sm)
                    .fill(Color.edgelessSurface)

                // Level fill
                RoundedRectangle(cornerRadius: Radius.sm)
                    .fill(barColor)
                    .frame(width: geometry.size.width * CGFloat(min(level, 1.0)))
                    .animation(.easeOut(duration: 0.05), value: level)
            }
        }
        .frame(height: 8)
    }

    private var barColor: Color {
        if isTransient {
            return .edgelessAccent
        } else if level > 0.1 {
            return .audioIndigo
        } else {
            return .audioIndigoMuted
        }
    }
}
