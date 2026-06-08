import SwiftUI

/// Settings view for configuring gesture-to-action mappings.
struct SettingsView: View {
    @ObservedObject var viewModel: ClapperViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                // Section: Gesture Mappings
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("Gesture Mappings")
                        .font(.edgelessHeadline)
                        .foregroundStyle(Color.edgelessTextPrimary)

                    Text("Choose what happens when each gesture is detected.")
                        .font(.edgelessCaption)
                        .foregroundStyle(Color.edgelessTextSecondary)

                    ForEach(viewModel.actionDispatcher.mappings) { mapping in
                        GestureMappingRow(
                            mapping: mapping,
                            onActionChanged: { newAction in
                                viewModel.actionDispatcher.updateMapping(
                                    gesture: mapping.gesture,
                                    action: newAction
                                )
                            }
                        )
                    }
                }

                Divider().background(Color.edgelessSurface)

                // Section: Detection Sensitivity
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("Detection")
                        .font(.edgelessHeadline)
                        .foregroundStyle(Color.edgelessTextPrimary)

                    VStack(spacing: Spacing.sm) {
                        HStack {
                            Text("Sensitivity")
                                .font(.edgelessBody)
                                .foregroundStyle(Color.edgelessTextSecondary)
                            Spacer()
                            Text(sensitivityLabel)
                                .font(.edgelessCaption)
                                .foregroundStyle(Color.edgelessTextTertiary)
                        }

                        Slider(value: $viewModel.sensitivity, in: 0...1, step: 0.05)
                            .tint(Color.edgelessAccent)
                    }
                    .padding(Spacing.base)
                    .background(Color.edgelessSurface)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                }

                Divider().background(Color.edgelessSurface)

                // Section: About
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("About")
                        .font(.edgelessHeadline)
                        .foregroundStyle(Color.edgelessTextPrimary)

                    HStack {
                        Text("Version")
                            .font(.edgelessBody)
                            .foregroundStyle(Color.edgelessTextSecondary)
                        Spacer()
                        Text("1.0.0")
                            .font(.edgelessCaption)
                            .foregroundStyle(Color.edgelessTextTertiary)
                    }

                    HStack {
                        Text("Edgeless Labs")
                            .font(.edgelessBody)
                            .foregroundStyle(Color.edgelessTextSecondary)
                        Spacer()
                        Text("edgelesslab.com")
                            .font(.edgelessCaption)
                            .foregroundStyle(Color.audioIndigo)
                    }
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.lg)
        }
        .background(Color.edgelessBackground)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var sensitivityLabel: String {
        switch viewModel.sensitivity {
        case 0..<0.3: return "Low"
        case 0.3..<0.7: return "Medium"
        default: return "High"
        }
    }
}

/// Row for configuring a single gesture -> action mapping.
struct GestureMappingRow: View {
    let mapping: GestureActionMapping
    let onActionChanged: (ActionType) -> Void

    var body: some View {
        HStack(spacing: Spacing.md) {
            // Gesture icon + name
            Image(systemName: mapping.gesture.icon)
                .font(.system(size: 20))
                .foregroundStyle(Color.edgelessAccent)
                .frame(width: 36, height: 36)
                .background(Color.edgelessAccent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(mapping.gesture.displayName)
                    .font(.edgelessBodyMedium)
                    .foregroundStyle(Color.edgelessTextPrimary)
            }

            Spacer()

            // Action picker
            Menu(content: {
                ForEach(ActionType.allCases) { action in
                    Button(action: { onActionChanged(action) }, label: {
                        Label(action.displayName, systemImage: action.icon)
                    })
                }
            }, label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: mapping.action.icon)
                        .font(.system(size: 14))
                    Text(mapping.action.displayName)
                        .font(.edgelessCaption)
                }
                .foregroundStyle(Color.edgelessTextSecondary)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(Color.edgelessSurface)
                .clipShape(Capsule())
            })
        }
        .padding(Spacing.base)
        .background(Color.edgelessSurface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }
}
