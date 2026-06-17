import SwiftUI

struct ContentView: View {
	@EnvironmentObject var appState: AppState

	var body: some View {
		NavigationSplitView {
			sidebar
		} detail: {
			detailView
		}
		.frame(minWidth: 900, minHeight: 600)
	}

	// MARK: - Sidebar

	private var sidebar: some View {
		List(selection: $appState.activeTab) {
			ForEach(SidebarTab.allCases) { tab in
				Label(tab.rawValue, systemImage: tab.icon)
					.tag(tab)
			}
		}
		.listStyle(.sidebar)
		.frame(minWidth: 180)
		.toolbar {
			ToolbarItem {
				Button(action: pickFolder) {
					Label("Add Folder", systemImage: "plus")
				}
			}
		}
	}

	// MARK: - Detail

	@ViewBuilder
	private var detailView: some View {
		switch appState.activeTab {
		case .watch:
			WatchView()
		case .folders:
			FolderPickerView()
		case .settings:
			SettingsView()
		case .results:
			SummaryTableView()
		}
	}

	// MARK: - Actions

	private func pickFolder() {
		let panel = NSOpenPanel()
		panel.canChooseDirectories = true
		panel.canChooseFiles = false
		panel.allowsMultipleSelection = true
		panel.prompt = "Select"
		panel.message = "Choose folders containing images to optimize"

		if panel.runModal() == .OK {
			for url in panel.urls {
				appState.addFolder(url)
			}
		}
	}
}
