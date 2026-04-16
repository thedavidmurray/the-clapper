import SwiftUI

/// Root content view with tab navigation between Home and Camera modes.
struct ContentView: View {
    @StateObject private var viewModel = ClapperViewModel()
    @State private var selectedTab = 0

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
                CameraView(viewModel: viewModel)
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
        }
    }
}
