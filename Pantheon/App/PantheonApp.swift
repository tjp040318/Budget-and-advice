import SwiftUI
import UIKit

@main
struct PantheonApp: App {
    @StateObject private var store: GameStore

    /// Explicitly main-actor isolated: `GameStore` is `@MainActor`, and building
    /// it in a default property value would leave that isolation implicit.
    @MainActor
    init() {
        _store = StateObject(wrappedValue: GameStore.bootstrap())

        // The whole app is dark; setting it here stops a light flash on launch
        // before the first SwiftUI frame applies the preference.
        UITabBar.appearance().backgroundColor = UIColor(Theme.ink)
        UINavigationBar.appearance().largeTitleTextAttributes = [
            .foregroundColor: UIColor(Theme.textPrimary)
        ]
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
        }
    }
}
