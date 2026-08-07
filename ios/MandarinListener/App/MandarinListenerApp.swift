import SwiftUI

@main
struct MandarinListenerApp: App {
    @StateObject private var settings: AppSettings
    @StateObject private var vocabularyStore: VocabularyStore
    @StateObject private var controller: SessionController

    init() {
        let settings = AppSettings()
        let vocabularyStore = VocabularyStore()
        _settings = StateObject(wrappedValue: settings)
        _vocabularyStore = StateObject(wrappedValue: vocabularyStore)
        _controller = StateObject(
            wrappedValue: SessionController(
                settings: settings,
                vocabularyStore: vocabularyStore
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(settings)
                .environmentObject(vocabularyStore)
                .environmentObject(controller)
                .preferredColorScheme(.dark)
        }
    }
}
