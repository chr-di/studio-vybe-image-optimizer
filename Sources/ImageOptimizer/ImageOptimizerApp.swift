import SwiftUI

@main
struct ImageOptimizerApp: App {
	@StateObject private var appState = AppState()
	@NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

	init() {
		// Register the bundled Inter faces before any view renders.
		FontLoader.register()
	}

	var body: some Scene {
		WindowGroup {
			ContentView()
				.environmentObject(appState)
				.environment(\.font, Theme.font(13))   // Inter as the default font
				.preferredColorScheme(.light)            // fixed light/cream brand appearance
				.tint(Theme.accent)
				.onAppear {
					appState.loadPersistedState()
					appDelegate.appState = appState
				}
		}
		.windowStyle(.titleBar)
		.defaultSize(width: 1100, height: 750)
	}
}

/// Handles dock icon drop and open-with via NSApplicationDelegate
class AppDelegate: NSObject, NSApplicationDelegate {
	var appState: AppState?

	func application(_ application: NSApplication, open urls: [URL]) {
		appState?.handleDroppedURLs(urls)
	}
}
