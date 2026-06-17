import SwiftUI

struct WatchView: View {
	@EnvironmentObject var appState: AppState

	var body: some View {
		VStack(spacing: 0) {
			// Header
			header

			Divider()

			// Watched folders list or empty state
			if appState.watchedFolders.isEmpty {
				emptyState
			} else {
				watchedFoldersList
			}

			// Activity log
			if !appState.watchActivity.isEmpty {
				Divider()
				activityLog
			}
		}
		.background(Theme.background)
	}

	// MARK: - Header

	private var header: some View {
		VStack(alignment: .leading, spacing: Theme.spacingSmall) {
			HStack {
				Text("Watched Folders")
					.font(Theme.headline)
				Spacer()
				Button(action: pickWatchFolder) {
					Label("Add Folder", systemImage: "plus.circle")
						.font(Theme.callout)
				}
				.buttonStyle(.plain)
				.foregroundStyle(Theme.accent)
			}

			HStack {
				Toggle("Auto-optimize new images", isOn: $appState.watchAutoOptimize)
					.toggleStyle(.switch)

				Spacer()

				let activeCount = appState.watchedFolders.filter(\.isEnabled).count
				Text("\(activeCount) folder\(activeCount == 1 ? "" : "s") monitored")
					.font(Theme.callout)
					.foregroundStyle(Theme.textSecondary)
			}
		}
		.padding(.horizontal, Theme.spacingLarge)
		.padding(.vertical, Theme.spacing)
	}

	// MARK: - Empty State

	private var emptyState: some View {
		VStack(spacing: Theme.spacing) {
			Image(systemName: "eye.circle")
				.font(.system(size: 48))
				.foregroundStyle(Theme.textSecondary.opacity(0.5))
			Text("No watched folders")
				.font(Theme.title3)
				.foregroundStyle(Theme.textSecondary)
			Text("Add a folder to automatically optimize new images as they appear")
				.font(Theme.callout)
				.foregroundStyle(Theme.textSecondary)
				.multilineTextAlignment(.center)
			Button("Add Folder", action: pickWatchFolder)
				.buttonStyle(AccentButtonStyle())
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
	}

	// MARK: - Watched Folders List

	private var watchedFoldersList: some View {
		List {
			ForEach(appState.watchedFolders) { folder in
				watchedFolderRow(folder)
			}
		}
		.listStyle(.inset)
	}

	private func watchedFolderRow(_ folder: WatchedFolder) -> some View {
		HStack(spacing: Theme.spacing) {
			Image(systemName: folder.isEnabled ? "eye.fill" : "eye.slash")
				.foregroundStyle(folder.isEnabled ? Theme.accent : Theme.textSecondary)
				.frame(width: 24)

			VStack(alignment: .leading, spacing: 2) {
				Text(folder.url.lastPathComponent)
					.font(Theme.font(13, .medium))
				Text(folder.url.path)
					.font(Theme.caption)
					.foregroundStyle(Theme.textSecondary)
					.lineLimit(1)
					.truncationMode(.middle)
			}

			Spacer()

			if folder.isEnabled {
				HStack(spacing: 4) {
					Circle()
						.fill(Theme.success)
						.frame(width: 6, height: 6)
					Text("Monitoring")
						.font(Theme.caption)
						.foregroundStyle(Theme.success)
				}
			} else {
				Text("Paused")
					.font(Theme.caption)
					.foregroundStyle(Theme.textSecondary)
			}

			Toggle("", isOn: Binding(
				get: { folder.isEnabled },
				set: { _ in appState.toggleWatchedFolder(folder) }
			))
			.toggleStyle(.switch)
			.labelsHidden()

			Button(action: { appState.removeWatchedFolder(folder) }) {
				Image(systemName: "xmark.circle.fill")
					.foregroundStyle(Theme.textSecondary)
			}
			.buttonStyle(.plain)
		}
		.padding(.vertical, 4)
	}

	// MARK: - Activity Log

	private var activityLog: some View {
		VStack(alignment: .leading, spacing: Theme.spacingSmall) {
			Text("Recent Activity")
				.font(Theme.headline)
				.padding(.horizontal, Theme.spacingLarge)
				.padding(.top, Theme.spacing)

			List {
				ForEach(appState.watchActivity) { entry in
					HStack(spacing: 8) {
						Image(systemName: entry.success ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
							.foregroundStyle(entry.success ? Theme.success : Theme.error)
							.font(Theme.caption)

						Text(entry.filename)
							.font(Theme.callout)
							.lineLimit(1)

						Spacer()

						if let saved = entry.savedPercent {
							Text("\(String(format: "%.0f", saved))% saved")
								.font(Theme.caption.monospacedDigit())
								.foregroundStyle(Theme.success)
						}

						Text(entry.folder)
							.font(Theme.caption)
							.foregroundStyle(Theme.textSecondary)

						Text(entry.timestamp, style: .relative)
							.font(Theme.caption)
							.foregroundStyle(Theme.textSecondary)
					}
				}
			}
			.listStyle(.inset)
			.frame(maxHeight: 200)
		}
	}

	// MARK: - Actions

	private func pickWatchFolder() {
		let panel = NSOpenPanel()
		panel.canChooseDirectories = true
		panel.canChooseFiles = false
		panel.allowsMultipleSelection = false
		panel.prompt = "Watch"
		panel.message = "Choose a folder to monitor for new images"

		if panel.runModal() == .OK, let url = panel.url {
			appState.addWatchedFolder(url)
		}
	}
}
