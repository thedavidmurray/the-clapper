import SwiftUI

struct PaywallView: View {
    @EnvironmentObject var storeManager: StoreManager
    @State private var isShowingPurchase = false
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 60))
                .foregroundColor(Color.edgelessAccent)
            
            Text("The Clapper Pro")
                .font(.edgelessTitle)
                .foregroundColor(Color.edgelessTextPrimary)
            
            Text("Unlock unlimited claps, snap detection, and advanced analytics")
                .font(.edgelessBody)
                .foregroundColor(Color.edgelessTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(icon: "waveform.path", text: "Unlimited claps")
                FeatureRow(icon: "hand.tap", text: "Advanced snap detection")
                FeatureRow(icon: "chart.bar", text: "Detailed analytics")
                FeatureRow(icon: "crown", text: "Future pro features")
            }
            .padding()
            
            Button(action: {
                Task {
                    if let product = storeManager.products.first {
                        await storeManager.purchase(product)
                    }
                }
            }) {
                Text("Get Pro - $4.99")
                    .font(.edgelessBody.bold())
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.edgelessAccent)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal)
            
            Button(action: {
                Task {
                    await storeManager.restorePurchases()
                }
            }) {
                Text("Restore Purchase")
                    .font(.edgelessCaption)
                    .foregroundColor(Color.edgelessTextTertiary)
            }
            .padding(.top, 8)
            
            if let error = storeManager.error {
                Text(error.localizedDescription)
                    .font(.edgelessCaption)
                    .foregroundColor(.red)
                    .padding()
            }
            
            Spacer()
        }
        .padding()
        .preferredColorScheme(.dark)
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .frame(width: 24)
                .foregroundColor(Color.edgelessAccent)
            Text(text)
                .font(.edgelessBody)
                .foregroundColor(Color.edgelessTextPrimary)
            Spacer()
        }
    }
}