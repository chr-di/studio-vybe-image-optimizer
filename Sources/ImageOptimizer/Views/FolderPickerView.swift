import SwiftUI

struct FolderPickerView: View {
	@EnvironmentObject var appState: AppState

	@State private var expanded: Set<UUID> = []

	var body: some View {
		VStack(spacing: 0) {
			// Header with folder list
			folderList

			Divider()

			// Scan options bar
			scanOptionsBar

			Divider()

			// File list or empty state
			if appState.isScanning {
				ProgressView("Scanning...")
					.frame(maxWidth: .infinity, maxHeight: .infinity)
			} else if appState.scannedFiles.isEmpty {
				emptyState
			} else {
				fileList
					.layoutPriority(-1)
			}

			// Rename section (collapsible, global — between file list and action bar)
			if !appState.scannedFiles.isEmpty {
				Divider()
				renameSection
					.fixedSize(horizontal: false, vertical: true)
			}

			Divider()

			// Action bar
			actionBar
		}
		.background(Theme.background)
	}

	// MARK: - Folder List

	private var folderList: some View {
		VStack(alignment: .leading, spacing: Theme.spacingSmall) {
			HStack {
				Text("Folders")
					.font(Theme.headline)
				if !appState.folderJobs.isEmpty {
					Text("\(appState.folderJobs.count)")
						.font(Theme.caption)
						.foregroundStyle(Theme.textSecondary)
				}
				Spacer()
				Text("Each folder has its own settings")
					.font(Theme.caption)
					.foregroundStyle(Theme.textSecondary)
				Button(action: pickFolder) {
					Label("Add", systemImage: "plus.circle")
						.font(Theme.callout)
				}
				.buttonStyle(.plain)
				.foregroundStyle(Theme.accent)
			}
			.padding(.horizontal, Theme.spacingLarge)
			.padding(.top, Theme.spacing)

			if appState.folderJobs.isEmpty {
				Text("No folders added. Click 'Add' to choose folders to optimize.")
					.foregroundStyle(Theme.textSecondary)
					.font(Theme.callout)
					.padding(.horizontal, Theme.spacingLarge)
					.padding(.bottom, Theme.spacing)
			} else {
				ScrollView {
					VStack(spacing: Theme.spacingSmall) {
						ForEach($appState.folderJobs) { $job in
							folderRow($job)
						}
					}
					.padding(.horizontal, Theme.spacingLarge)
					.padding(.bottom, Theme.spacing)
				}
				.frame(maxHeight: 340)
			}
		}
	}

	private func folderRow(_ job: Binding<FolderJob>) -> some View {
		let id = job.wrappedValue.id
		let isExpanded = expanded.contains(id)
		return VStack(alignment: .leading, spacing: 0) {
			HStack(spacing: Theme.spacingSmall) {
				Button {
					if isExpanded { expanded.remove(id) } else { expanded.insert(id) }
				} label: {
					HStack(spacing: Theme.spacingSmall) {
						Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
							.font(Theme.caption)
							.foregroundStyle(Theme.textSecondary)
							.frame(width: 12)
						Image(systemName: "folder.fill")
							.foregroundStyle(Theme.accent)
							.font(Theme.callout)
						VStack(alignment: .leading, spacing: 1) {
							Text(job.wrappedValue.url.lastPathComponent)
								.font(Theme.font(13, .medium))
								.lineLimit(1)
							Text(job.wrappedValue.config.summary)
								.font(Theme.caption)
								.foregroundStyle(Theme.textSecondary)
								.lineLimit(1)
						}
						Spacer()
					}
					.contentShape(Rectangle())
				}
				.buttonStyle(.plain)

				Button(action: { appState.removeFolder(job.wrappedValue.url) }) {
					Image(systemName: "xmark.circle.fill")
						.foregroundStyle(Theme.textSecondary)
						.font(Theme.callout)
				}
				.buttonStyle(.plain)
			}
			.padding(.horizontal, Theme.spacing)
			.padding(.vertical, Theme.spacingSmall)

			if isExpanded {
				Divider()
				CompressionConfigEditor(config: job.config)
					.padding(Theme.spacing)
			}
		}
		.background(Theme.surface)
		.clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
		.overlay(
			RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall)
				.stroke(Theme.border, lineWidth: 0.5)
		)
	}

	// MARK: - Scan Options

	private var scanOptionsBar: some View {
		HStack(spacing: Theme.spacingLarge) {
			Toggle("Recursive", isOn: Binding(
				get: { appState.settings.recursive },
				set: { appState.settings.recursive = $0; appState.scanFolders() }
			))
			.toggleStyle(.switch)

			Toggle("Skip optimized", isOn: Binding(
				get: { appState.settings.skipAlreadyOptimized },
				set: { appState.settings.skipAlreadyOptimized = $0 }
			))
			.toggleStyle(.switch)

			Spacer()

			Text("\(appState.scannedFiles.count) files found")
				.font(Theme.callout)
				.foregroundStyle(Theme.textSecondary)

			Text(formatBytes(appState.totalOriginalSize))
				.font(Theme.callout.monospacedDigit())
				.foregroundStyle(Theme.textSecondary)
		}
		.padding(.horizontal, Theme.spacingLarge)
		.padding(.vertical, Theme.spacingSmall)
		.background(Theme.surfaceSecondary)
	}

	// MARK: - File List

	private var fileList: some View {
		Table(appState.scannedFiles) {
			TableColumn("Name") { file in
				HStack(spacing: 6) {
					formatBadge(file.format)
					Text(file.filename)
						.lineLimit(1)
				}
			}
			.width(min: 200)

			TableColumn("Path") { file in
				Text(file.relativePath)
					.foregroundStyle(Theme.textSecondary)
					.lineLimit(1)
			}
			.width(min: 150)

			TableColumn("Size") { file in
				Text(formatBytes(file.originalSize))
					.monospacedDigit()
			}
			.width(80)

			TableColumn("Dimensions") { file in
				if let w = file.width, let h = file.height {
					Text("\(w) × \(h)")
						.monospacedDigit()
				} else {
					Text("—")
						.foregroundStyle(Theme.textSecondary)
				}
			}
			.width(100)
		}
	}

	// MARK: - Empty State

	private var emptyState: some View {
		VStack(spacing: Theme.spacing) {
			Image(systemName: "photo.on.rectangle.angled")
				.font(.system(size: 48))
				.foregroundStyle(Theme.textSecondary.opacity(0.5))
			Text("Select folders to scan for images")
				.font(Theme.title3)
				.foregroundStyle(Theme.textSecondary)
			Button("Choose Folders", action: pickFolder)
				.buttonStyle(AccentButtonStyle())
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
	}

	// MARK: - Rename Section

	private var renameSection: some View {
		VStack(alignment: .leading, spacing: 0) {
			HStack {
				Image(systemName: appState.renameSettings.enabled ? "chevron.down" : "chevron.right")
					.font(Theme.caption)
					.foregroundStyle(Theme.textSecondary)
					.frame(width: 12)
				Toggle("Rename outputs", isOn: Binding(
					get: { appState.renameSettings.enabled },
					set: { newValue in
						withAnimation(.easeInOut(duration: 0.2)) {
							appState.renameSettings.enabled = newValue
						}
					}
				))
				.toggleStyle(.switch)
				Spacer()
				if appState.renameSettings.enabled {
					Text(renamePreviewSummary)
						.font(Theme.caption)
						.foregroundStyle(Theme.textSecondary)
				}
			}
			.padding(.horizontal, Theme.spacingLarge)
			.padding(.vertical, Theme.spacingSmall)

			if appState.renameSettings.enabled {
				VStack(alignment: .leading, spacing: Theme.spacingSmall) {
					// Mode picker
					Picker("Mode", selection: $appState.renameSettings.mode) {
						ForEach(RenameMode.allCases) { mode in
							Text(mode.rawValue).tag(mode)
						}
					}
					.pickerStyle(.segmented)

					// Mode-specific controls
					renameControls

					// Inline preview
					if !appState.scannedFiles.isEmpty {
						renamePreview
					}
				}
				.padding(.horizontal, Theme.spacingLarge)
				.padding(.bottom, Theme.spacingSmall)
				.transition(.opacity.combined(with: .move(edge: .top)))
			}
		}
		.background(Theme.surfaceSecondary)
	}

	@ViewBuilder
	private var renameControls: some View {
		switch appState.renameSettings.mode {
		case .prefixSuffix:
			HStack(spacing: Theme.spacing) {
				HStack {
					Text("Prefix:")
						.font(Theme.callout)
					TextField("e.g. optimized-", text: $appState.renameSettings.prefix)
						.textFieldStyle(.roundedBorder)
				}
				HStack {
					Text("Suffix:")
						.font(Theme.callout)
					TextField("e.g. -opt", text: $appState.renameSettings.suffix)
						.textFieldStyle(.roundedBorder)
				}
			}
		case .findReplace:
			HStack(spacing: Theme.spacing) {
				HStack {
					Text("Find:")
						.font(Theme.callout)
					TextField("Text to find", text: $appState.renameSettings.findText)
						.textFieldStyle(.roundedBorder)
				}
				HStack {
					Text("Replace:")
						.font(Theme.callout)
					TextField("Replacement", text: $appState.renameSettings.replaceText)
						.textFieldStyle(.roundedBorder)
				}
			}
		case .regex:
			HStack(spacing: Theme.spacing) {
				HStack {
					Text("Pattern:")
						.font(Theme.callout)
					TextField("Regex", text: $appState.renameSettings.regexPattern)
						.textFieldStyle(.roundedBorder)
				}
				HStack {
					Text("Replace:")
						.font(Theme.callout)
					TextField("$1, $2...", text: $appState.renameSettings.regexReplacement)
						.textFieldStyle(.roundedBorder)
				}
			}
		case .sequential:
			HStack(spacing: Theme.spacing) {
				HStack {
					Text("Template:")
						.font(Theme.callout)
					TextField("IMG_{n}", text: $appState.renameSettings.sequentialTemplate)
						.textFieldStyle(.roundedBorder)
				}
				Stepper("Pad: \(appState.renameSettings.sequentialPadding)", value: $appState.renameSettings.sequentialPadding, in: 1...6)
					.font(Theme.callout)
				Stepper("Start: \(appState.renameSettings.sequentialStart)", value: $appState.renameSettings.sequentialStart, in: 0...9999)
					.font(Theme.callout)
			}
		}
	}

	private var renamePreview: some View {
		HStack(spacing: Theme.spacing) {
			ForEach(Array(appState.scannedFiles.prefix(3).enumerated()), id: \.element.id) { index, file in
				HStack(spacing: 4) {
					Text(file.nameWithoutExtension)
						.font(Theme.caption)
						.foregroundStyle(Theme.textSecondary)
						.lineLimit(1)
					Image(systemName: "arrow.right")
						.font(Theme.caption2)
						.foregroundStyle(Theme.accent)
					Text(appState.renameSettings.apply(to: file.nameWithoutExtension, index: index))
						.font(Theme.font(11, .medium))
						.lineLimit(1)
				}
			}
			if appState.scannedFiles.count > 3 {
				Text("+\(appState.scannedFiles.count - 3) more")
					.font(Theme.caption)
					.foregroundStyle(Theme.textSecondary)
			}
			Spacer()
		}
	}

	private var renamePreviewSummary: String {
		guard let first = appState.scannedFiles.first else { return "" }
		let renamed = appState.renameSettings.apply(to: first.nameWithoutExtension, index: 0)
		return "\(first.nameWithoutExtension) → \(renamed)"
	}

	// MARK: - Action Bar

	private var actionBar: some View {
		HStack {
			if appState.isProcessing {
				ProgressView(value: appState.progress) {
					Text("Processing: \(appState.currentFile)")
						.font(Theme.callout)
				}
				.progressViewStyle(.linear)
			} else {
				Spacer()
			}

			HStack(spacing: Theme.spacing) {
				Toggle("Dry run", isOn: $appState.isDryRun)
					.toggleStyle(.switch)

				Toggle("Preview (10 files)", isOn: $appState.isPreviewMode)
					.toggleStyle(.switch)

				if appState.renameSettings.enabled {
					Button("Rename Only") {
						appState.startRenameOnly()
					}
					.buttonStyle(.bordered)
					.disabled(appState.scannedFiles.isEmpty || appState.isProcessing)
				}

				Button(appState.isProcessing ? "Processing..." : "Optimize") {
					appState.startProcessing()
				}
				.buttonStyle(AccentButtonStyle())
				.disabled(appState.scannedFiles.isEmpty || appState.isProcessing)
			}
		}
		.padding(.horizontal, Theme.spacingLarge)
		.padding(.vertical, Theme.spacing)
	}

	// MARK: - Helpers

	private func pickFolder() {
		let panel = NSOpenPanel()
		panel.canChooseDirectories = true
		panel.canChooseFiles = false
		panel.allowsMultipleSelection = true
		panel.prompt = "Select"
		if panel.runModal() == .OK {
			for url in panel.urls {
				appState.addFolder(url)
			}
		}
	}

	private func formatBadge(_ format: ImageFormat) -> some View {
		Text(format.rawValue)
			.font(Theme.font(10, .medium))
			.padding(.horizontal, 5)
			.padding(.vertical, 2)
			.background(badgeColor(format).opacity(0.15))
			.foregroundStyle(badgeColor(format))
			.clipShape(RoundedRectangle(cornerRadius: 3))
	}

	private func badgeColor(_ format: ImageFormat) -> Color {
		switch format {
		case .jpeg: return .orange
		case .png: return .blue
		case .webp: return .green
		case .avif: return .purple
		}
	}
}

// MARK: - Byte Formatting

func formatBytes(_ bytes: Int64) -> String {
	let formatter = ByteCountFormatter()
	formatter.countStyle = .file
	return formatter.string(fromByteCount: bytes)
}

// MARK: - Accent Button Style

struct AccentButtonStyle: ButtonStyle {
	var isDestructive: Bool = false

	func makeBody(configuration: Configuration) -> some View {
		configuration.label
			.font(Theme.font(13, .semibold))
			.padding(.horizontal, 20)
			.padding(.vertical, 8)
			.background(configuration.isPressed
				? (isDestructive ? Theme.destructive : Theme.accentHover)
				: (isDestructive ? Theme.destructive : Theme.accent))
			.foregroundStyle(isDestructive ? Color.white : Theme.onAccent)
			.clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
			.opacity(configuration.isPressed ? 0.95 : 1)
	}
}
