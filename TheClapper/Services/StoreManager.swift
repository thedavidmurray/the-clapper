import StoreKit

@MainActor
class StoreManager: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasedProductIDs: Set<String> = []
    @Published private(set) var purchaseState: PurchaseState?
    @Published private(set) var error: Error?
    
    private var updates: Task<Void, Never>? = nil
    private let productIDs: Set<String> = ["com.edgeless.theclapper.pro"]
    
    enum PurchaseState {
        case purchasing
        case purchased
        case deferred
        case failed(Error)
    }
    
    deinit {
        updates?.cancel()
    }
    
    init() {
        updates = observeTransactionUpdates()
        Task {
            await requestProducts()
            await updateCustomerProductStatus()
        }
    }
    
    func requestProducts() async {
        do {
            products = try await Product.products(for: productIDs)
        } catch {
            self.error = error
        }
    }
    
    func purchase(_ product: Product) async {
        do {
            purchaseState = .purchasing
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .unverified(_, let error):
                    purchaseState = .failed(error)
                case .verified(let transaction):
                    await updateTransaction(transaction)
                }
            case .userCancelled:
                purchaseState = nil
                break
            case .pending:
                purchaseState = .deferred
            }
        } catch {
            purchaseState = .failed(error)
            self.error = error
        }
    }
    
    func restorePurchases() async {
        do {
            try await AppStore.sync()
        } catch {
            self.error = error
        }
    }
    
    private func updateTransaction(_ transaction: Transaction) async {
        // Deliver the product to the user.
        await updateCustomerProductStatus()
        await transaction.finish()
        purchaseState = .purchased
    }
    
    private func updateCustomerProductStatus() async {
        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                // Check if the transaction is for one of our product IDs and is not revoked.
                if productIDs.contains(transaction.productID) && transaction.revocationDate == nil {
                    purchasedProductIDs.insert(transaction.productID)
                }
            case .unverified(let error, _):
                print("Error reading transaction: \(error)")
            }
        }
    }
    
    private func observeTransactionUpdates() -> Task<Void, Never> {
        Task(priority: .background) { [unowned self] in
            for await verification in Transaction.updates {
                switch verification {
                case .verified(let transaction):
                    // Check if the transaction is for one of our product IDs and is not revoked.
                    if productIDs.contains(transaction.productID) && transaction.revocationDate == nil {
                        await updateCustomerProductStatus()
                    }
                    await transaction.finish()
                case .unverified(let error, _):
                    print("Transaction verification failed: \(error)")
                }
            }
        }
    }
    
    func isPurchased(_ productID: String) -> Bool {
        return purchasedProductIDs.contains(productID)
    }
}
