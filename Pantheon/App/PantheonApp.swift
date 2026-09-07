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

        #if DEBUG
        // Reports, once, which models are really in the app and which are
        // standing in. A placeholder and a model that failed to load look
        // identical on screen; this is the only place the difference shows.
        ModelLibrary.shared.diagnose(
            expecting: UnitDatabase.all.map { $0.model.assetName }
        )
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
        }
    }
}
