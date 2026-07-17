import SwiftUI

struct PaywallView: View {
    @EnvironmentObject var storeManager: StoreManager
    
    var body: some View {
        VStack(spacing: 20) {
            Text("The Clapper Pro")
                .font(.title)
                .bold()
            
            Text("Unlock all features with a one-time purchase")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Button(action: {
                Task {
                    await storeManager.purchase("com.edgeless.theclapper.pro")
                }
            }) {
                Text("Buy Now - $1.99")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .Background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .buttonStyle(.plain)
            
            Button("Restore Purchase") {
                Task {
                    await storeManager.restorePurchases()
                }
            }
            .foregroundColor(.blue)
        }
        .padding()
    }
}
