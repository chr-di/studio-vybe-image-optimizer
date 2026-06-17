import SwiftUI

/// Reusable editor for a `FolderCompression` — used both per-folder in the Folders tab
/// and for the global "Default job settings" block in the Settings tab.
struct CompressionConfigEditor: View {
	@Binding var config: FolderCompression

	var body: some View {
		VStack(alignment: .leading, spacing: Theme.spacing) {
			Picker("Mode", selection: $config.compressionMode) {
				ForEach(CompressionMode.allCases) { mode in
					Text(mode.rawValue).tag(mode)
				}
			}
			.pickerStyle(.segmented)

			if config.compressionMode == .quality {
				qualityControls
			}

			formatSelection

			Divider().padding(.vertical, 2)

			resizeControls
		}
	}

	// MARK: - Quality (single slider, applies to all chosen formats)

	private var qualityControls: some View {
		VStack(alignment: .leading, spacing: Theme.spacingSmall) {
			HStack {
				Text("Quality: \(config.quality)")
					.font(Theme.callout.monospacedDigit())
				Spacer()
				ForEach(QualityPreset.allCases) { preset in
					Button(preset.rawValue) { config.quality = preset.value }
						.buttonStyle(.bordered)
						.controlSize(.small)
						.tint(config.quality == preset.value ? Theme.accent : nil)
				}
			}
			Slider(value: Binding(
				get: { Double(config.quality) },
				set: { config.quality = Int($0) }
			), in: 1...100, step: 1)
		}
	}

	// MARK: - Output formats (which formats to emit, + per-format target in target mode)

	private var formatSelection: some View {
		VStack(alignment: .leading, spacing: Theme.spacingSmall) {
			Text(config.compressionMode == .targetSize
				? "Output formats and the max file size for each. Tick a format to produce it for every image."
				: "Output formats to produce for every image.")
				.font(Theme.caption)
				.foregroundStyle(Theme.textSecondary)

			ForEach(ImageFormat.allCases) { fmt in
				formatRow(fmt)
			}

			Toggle("Keep original format", isOn: $config.keepSourceFormat)
				.toggleStyle(.switch)
			Text("Also optimize each image in its own source format (in addition to any ticked above).")
				.font(Theme.caption)
				.foregroundStyle(Theme.textSecondary)

			if config.compressionMode == .targetSize {
				Toggle("Allow downscaling to reach target", isOn: $config.allowDownscaleToTarget)
					.toggleStyle(.switch)
				if !ImageProcessor.pngquantAvailable {
					Label("pngquant not installed — PNG targets rely on downscaling. Install with: brew install pngquant",
						  systemImage: "info.circle")
						.font(Theme.caption)
						.foregroundStyle(Theme.warning)
				}
			}
		}
	}

	private func formatRow(_ fmt: ImageFormat) -> some View {
		HStack(spacing: Theme.spacing) {
			Toggle(fmt.rawValue, isOn: Binding(
				get: { config.outputFormats.contains(fmt) },
				set: { on in
					if on { config.outputFormats.insert(fmt) } else { config.outputFormats.remove(fmt) }
				}
			))
			.toggleStyle(.checkbox)
			.frame(width: 84, alignment: .leading)

			if config.compressionMode == .targetSize {
				TextField("KB", value: targetBinding(fmt), format: .number)
					.textFieldStyle(.roundedBorder)
					.frame(width: 90)
					.monospacedDigit()
				Text("KB")
					.font(Theme.caption)
					.foregroundStyle(Theme.textSecondary)
				Stepper("", value: targetBinding(fmt), in: 5...50_000, step: 10)
					.labelsHidden()
				Spacer()
				ForEach([100, 250, 500], id: \.self) { preset in
					Button("\(preset)") { config.targetSizes[fmt] = preset }
						.buttonStyle(.bordered)
						.controlSize(.small)
						.tint(config.targetSizes[fmt] == preset ? Theme.accent : nil)
				}
			} else {
				Spacer()
			}
		}
	}

	private func targetBinding(_ fmt: ImageFormat) -> Binding<Int> {
		Binding(
			get: { config.targetSizes[fmt] },
			set: { config.targetSizes[fmt] = $0 }
		)
	}

	// MARK: - Resize

	private var dimensionBinding: Binding<Int> {
		Binding(
			get: { config.maxDimension ?? 2048 },
			set: { config.maxDimension = $0 }
		)
	}

	private var resizeControls: some View {
		VStack(alignment: .leading, spacing: Theme.spacingSmall) {
			Toggle("Resize images", isOn: Binding(
				get: { config.maxDimension != nil },
				set: { on in config.maxDimension = on ? (config.maxDimension ?? 2048) : nil }
			))
			.toggleStyle(.switch)

			if config.maxDimension != nil {
				Picker("", selection: $config.resizeMode) {
					ForEach(ResizeMode.allCases) { mode in
						Text(mode.rawValue).tag(mode)
					}
				}
				.pickerStyle(.segmented)
				.labelsHidden()

				HStack(spacing: Theme.spacing) {
					TextField("px", value: dimensionBinding, format: .number)
						.textFieldStyle(.roundedBorder)
						.frame(width: 80)
						.monospacedDigit()
					Text("px max \(config.resizeMode.rawValue.lowercased())")
						.font(Theme.caption)
						.foregroundStyle(Theme.textSecondary)
					Spacer()
					ForEach([1024, 1920, 2048, 4096], id: \.self) { preset in
						Button("\(preset)") { config.maxDimension = preset }
							.buttonStyle(.bordered)
							.controlSize(.small)
							.tint(config.maxDimension == preset ? Theme.accent : nil)
					}
				}
			}
		}
	}
}
