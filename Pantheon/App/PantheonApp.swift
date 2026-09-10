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

        // Decode the sound set now so the first hit of the first battle does
        // not stutter. Off the main thread; a missing file is a silent event.
        AudioLibrary.shared.preload()

        // The main-thread watchdog: any stall over a quarter second is
        // written to More → Diagnostics with its length and the time.
        Perf.startWatchdog()

        #if DEBUG
        // Line-buffered stdout. The CI tour writes the app's stdout to a
        // file and kills the app at the end of each step; a block-buffered
        // stdout took the last kilobytes with it — every run's wave-three
        // loads and the watchdog's lines were in the buffer, not the file.
        setvbuf(stdout, nil, _IOLBF, 0)
        #endif

        // Build the unit database and the bundle's resource index before a
        // screen asks for them. `UnitDatabase.all` is three hundred and
        // ninety-five blueprints and `summonPool` filters every one of them on
        // whether its card shipped; whichever screen touched it first paid for
        // all of it on the main thread, which is why the arena took seconds to
        // open. Swift's lazy static initialisation is thread-safe, so warming
        // it here is only a matter of who waits.
        DispatchQueue.global(qos: .userInitiated).async {
            _ = UnitDatabase.summonPool
            _ = StageDatabase.allStages.count
        }

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
            #if DEBUG
            // `-tour` is the CI screenshot job: the app drives itself through
            // its screens while the runner photographs the simulator.
            if ProcessInfo.processInfo.arguments.contains("-tour") {
                TourView()
                    .environmentObject(store)
            } else {
                RootView()
                    .environmentObject(store)
            }
            #else
            RootView()
                .environmentObject(store)
            #endif
        }
    }
}
