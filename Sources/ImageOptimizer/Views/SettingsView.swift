import SwiftUI

struct SettingsView: View {
	@EnvironmentObject var appState: AppState

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: Theme.spacingLarge) {
				// Default job settings applied to newly added folders
				settingsSection("Default Job Settings") {
					VStack(alignment: .leading, spacing: Theme.spacingSmall) {
						Text("Applied to a folder when you add it. Override compression, format, and resize per folder in the Folders tab.")
							.font(Theme.caption)
							.foregroundStyle(Theme.textSecondary)
						CompressionConfigEditor(config: $appState.settings.compression)
					}
				}

				// Per-Format Settings
				settingsSection("JPEG Settings") {
					jpegSettings
				}

				settingsSection("PNG Settings") {
					pngSettings
				}

				settingsSection("WebP Settings") {
					webpSettings
				}

				settingsSection("AVIF Settings") {
					avifSettings
				}

				// Drop Output Folder
				settingsSection("Dock Drop Output") {
					dropOutputSettings
				}

// Include/Exclude Patterns
				settingsSection("File Patterns") {
					patternSettings
				}
			}
			.padding(Theme.spacingLarge)
		}
		.background(Theme.background)
	}

	// MARK: - Per-Format Settings

	private var jpegSettings: some View {
		VStack(alignment: .leading, spacing: Theme.spacingSmall) {
			Toggle("Progressive JPEG", isOn: $appState.settings.jpeg.progressive)
			Toggle("Strip metadata", isOn: $appState.settings.jpeg.stripMetadata)

			HStack(spacing: 4) {
				Image(systemName: jpegEncoderIcon)
					.foregroundStyle(jpegEncoderColor)
					.font(Theme.caption)
				Text(jpegEncoderStatus)
					.font(Theme.caption)
					.foregroundStyle(Theme.textSecondary)
			}
		}
	}

	private var jpegliInstalled: Bool {
		["/opt/homebrew/bin/cjpegli", "/usr/local/bin/cjpegli",
		 "/opt/homebrew/opt/jpeg-xl/bin/cjpegli", "/usr/local/opt/jpeg-xl/bin/cjpegli"]
			.contains { FileManager.default.fileExists(atPath: $0) }
	}

	private var mozJPEGInstalled: Bool {
		["/opt/homebrew/opt/mozjpeg/bin/cjpeg", "/usr/local/opt/mozjpeg/bin/cjpeg"]
			.contains { FileManager.default.fileExists(atPath: $0) }
	}

	private var jpegEncoderIcon: String {
		if jpegliInstalled { return "checkmark.circle.fill" }
		if mozJPEGInstalled { return "checkmark.circle.fill" }
		return "info.circle"
	}

	private var jpegEncoderColor: Color {
		if jpegliInstalled || mozJPEGInstalled { return .green }
		return Theme.textSecondary
	}

	private var jpegEncoderStatus: String {
		if jpegliInstalled {
			return "Using Jpegli (Google) — best-in-class, ~35% smaller than standard JPEG"
		}
		if mozJPEGInstalled {
			return "Using MozJPEG — 10-15% smaller than standard JPEG"
		}
		return "Using macOS native. Install for better compression: brew install mozjpeg"
	}

	private var pngSettings: some View {
		VStack(alignment: .leading, spacing: Theme.spacingSmall) {
			Picker("Engine", selection: $appState.settings.png.engine) {
				ForEach(PNGSettings.PNGEngine.allCases) { engine in
					Text(engine.rawValue).tag(engine)
				}
			}
			.pickerStyle(.segmented)

			Text(pngEngineDescription)
				.font(Theme.caption)
				.foregroundStyle(Theme.textSecondary)
		}
	}

	private var pngEngineDescription: String {
		switch appState.settings.png.engine {
		case .pngquantOxipng:
			return "Lossy color quantization + lossless recompression. Best balance of size and speed."
		case .oxipng:
			return "Lossless DEFLATE optimization only. No color reduction."
		case .zopflipng:
			return "Maximum lossless compression via Zopfli. Very slow but smallest output."
		}
	}

	private var webpSettings: some View {
		VStack(alignment: .leading, spacing: Theme.spacingSmall) {
			Toggle("Lossy compression", isOn: $appState.settings.webp.lossy)

			HStack {
				Text("Effort: \(appState.settings.webp.effort)")
					.font(Theme.callout.monospacedDigit())
				Slider(value: Binding(
					get: { Double(appState.settings.webp.effort) },
					set: { appState.settings.webp.effort = Int($0) }
				), in: 0...6, step: 1)
			}
		}
	}

	private var avifSettings: some View {
		VStack(alignment: .leading, spacing: Theme.spacingSmall) {
			HStack {
				Text("Quality (CQ): \(appState.settings.avif.quality)")
					.font(Theme.callout.monospacedDigit())
				Slider(value: Binding(
					get: { Double(appState.settings.avif.quality) },
					set: { appState.settings.avif.quality = Int($0) }
				), in: 0...63, step: 1)
			}
			Text("Lower = better quality")
				.font(Theme.caption)
				.foregroundStyle(Theme.textSecondary)

			HStack {
				Text("Effort: \(appState.settings.avif.effort)")
					.font(Theme.callout.monospacedDigit())
				Slider(value: Binding(
					get: { Double(appState.settings.avif.effort) },
					set: { appState.settings.avif.effort = Int($0) }
				), in: 0...10, step: 1)
			}
		}
	}

	// MARK: - Drop Output Folder

	private var dropOutputSettings: some View {
		VStack(alignment: .leading, spacing: Theme.spacingSmall) {
			Text("Default folder for images dropped on the dock icon.")
				.font(Theme.caption)
				.foregroundStyle(Theme.textSecondary)

			if let folder = appState.dropOutputFolder {
				HStack {
					Image(systemName: "folder.fill")
						.foregroundStyle(Theme.accent)
					Text(folder.path)
						.font(Theme.callout)
						.lineLimit(1)
						.truncationMode(.middle)
					Spacer()
					Button("Change") {
						pickDropOutputFolder()
					}
					.buttonStyle(.bordered)
					.controlSize(.small)
					Button("Clear") {
						appState.clearDropOutputFolder()
					}
					.buttonStyle(.bordered)
					.controlSize(.small)
					.tint(Theme.destructive)
				}
			} else {
				HStack {
					Text("Not set — outputs go to optimized/ next to source files")
						.font(Theme.callout)
						.foregroundStyle(Theme.textSecondary)
					Spacer()
					Button("Choose Folder") {
						pickDropOutputFolder()
					}
					.buttonStyle(.bordered)
					.controlSize(.small)
				}
			}
		}
	}

	private func pickDropOutputFolder() {
		let panel = NSOpenPanel()
		panel.canChooseDirectories = true
		panel.canChooseFiles = false
		panel.allowsMultipleSelection = false
		panel.message = "Choose default output folder for dock drop optimization"
		panel.prompt = "Select"
		if panel.runModal() == .OK, let url = panel.url {
			appState.setDropOutputFolder(url)
		}
	}

	// MARK: - File Patterns

	private var patternSettings: some View {
		VStack(alignment: .leading, spacing: Theme.spacingSmall) {
			Text("Include patterns (comma-separated):")
				.font(Theme.callout)
			TextField("*.jpg, *.png, *.webp", text: Binding(
				get: { appState.settings.includePatterns.joined(separator: ", ") },
				set: { appState.settings.includePatterns = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
			))
			.textFieldStyle(.roundedBorder)

			Text("Exclude patterns (comma-separated):")
				.font(Theme.callout)
			TextField("*-thumbnail.*", text: Binding(
				get: { appState.settings.excludePatterns.joined(separator: ", ") },
				set: { appState.settings.excludePatterns = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
			))
			.textFieldStyle(.roundedBorder)
		}
	}

	// MARK: - Section Helper

	private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
		VStack(alignment: .leading, spacing: Theme.spacingSmall) {
			Text(title)
				.font(Theme.headline)
			content()
		}
		.padding(Theme.spacing)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(Theme.surface)
		.clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
		.overlay(
			RoundedRectangle(cornerRadius: Theme.cornerRadius)
				.stroke(Theme.border, lineWidth: 0.5)
		)
	}
}
