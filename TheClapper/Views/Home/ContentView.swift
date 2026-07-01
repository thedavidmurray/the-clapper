import SwiftUI

/// Root content view with tab navigation between Home and Camera modes.
struct ContentView: View {
    @StateObject private var viewModel = ClapperViewModel()
    @State private var selectedTab = 0
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $selectedTab) {
            // Home / Monitor tab
            NavigationStack {
                HomeView(viewModel: viewModel)
            }
            .tabItem {
                Image(systemName: "waveform")
                Text("Monitor")
            }
            .tag(0)

            // Camera tab
            NavigationStack {
                CameraView(viewModel: viewModel, selectedTab: $selectedTab)
            }
            .tabItem {
                Image(systemName: "video.fill")
                Text("Camera")
            }
            .tag(1)

            // Settings tab
            NavigationStack {
                SettingsView(viewModel: viewModel)
            }
            .tabItem {
                Image(systemName: "gearshape")
                Text("Settings")
            }
            .tag(2)
        }
        .tint(Color.edgelessAccent)
        .task {
            await viewModel.requestPermissions()
            viewModel.startListening()   // auto-listen while the app is open
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                viewModel.startListening()          // resume on return to foreground
            case .background:
                viewModel.handleEnteredBackground()  // release mic unless Background Listening is on
            default:
                break
            }
        }
    }
}
