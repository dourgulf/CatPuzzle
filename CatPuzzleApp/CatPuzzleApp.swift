import SwiftUI

@main
struct CatPuzzleApp: App {
    @StateObject private var session: AppSession

    init() {
        _session = StateObject(
            wrappedValue: AppSession(
                progressStore: UserDefaultsGameProgressStore()
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView(session: session)
        }
    }
}
