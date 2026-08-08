import SwiftUI

@main
struct TheClapperApp: App {
    @StateObject private var storeManager = StoreManager()
    
    var body: some Scene {
        WindowGroup {
            if storeManager.isPurchased("com.edgeless.theclapper.pro") {
                ContentView()
                    .preferredColorScheme(.dark)
                    .environmentObject(storeManager)
            } else {
                PaywallView()
                    .preferredColorScheme(.dark)
                    .environmentObject(storeManager)
            }
        }
    }
}
