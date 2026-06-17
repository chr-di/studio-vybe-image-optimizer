import SwiftUI

struct SummaryTableView: View {
	@EnvironmentObject var appState: AppState

	var body: some View {
		VStack(spacing: 0) {
			// Summary header
			if !appState.results.isEmpty {
				summaryHeader
				Divider()
			}

			// Results table or empty state
			if appState.results.isEmpty {
				emptyState
			} else {
				resultsTable
			}
		}
		.background(Theme.background)
	}

	// MARK: - Summary Header

	private var summaryHeader: some View {
		HStack(spacing: Theme.spacingLarge) {
			statCard("Files", value: "\(appState.results.count)", icon: "doc")
			statCard("Original", value: formatBytes(appState.totalOriginalSize), icon: "arrow.down.doc")
			statCard("Optimized", value: formatBytes(appState.totalOptimizedSize), icon: "arrow.up.doc")
			statCard("Saved", value: "\(String(format: "%.1f", appState.savingsPercent))%", icon: "chart.line.downtrend.xyaxis")

			Spacer()

			if appState.isDryRun {
				Label("Dry Run", systemImage: "eye")
					.font(Theme.font(12, .medium))
					.foregroundStyle(Theme.warning)
					.padding(.horizontal, 12)
					.padding(.vertical, 6)
					.background(Theme.warning.opacity(0.1))
					.clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
			}

			let errors = appState.results.filter { !$0.isSuccess }.count
			if errors > 0 {
				Label("\(errors) errors", systemImage: "exclamationmark.triangle")
					.font(Theme.font(12, .medium))
					.foregroundStyle(Theme.error)
					.padding(.horizontal, 12)
					.padding(.vertical, 6)
					.background(Theme.error.opacity(0.1))
					.clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
			}
		}
		.padding(Theme.spacingLarge)
		.background(Theme.surface)
	}

	private func statCard(_ label: String, value: String, icon: String) -> some View {
		VStack(spacing: 4) {
			HStack(spacing: 4) {
				Image(systemName: icon)
					.font(Theme.caption)
					.foregroundStyle(Theme.accent)
				Text(value)
					.font(Theme.font(15, .semibold).monospacedDigit())
			}
			Text(label)
				.font(Theme.caption)
				.foregroundStyle(Theme.textSecondary)
		}
	}

	// MARK: - Results Table

	private var resultsTable: some View {
		Table(flattenedResults) {
			TableColumn("File") { row in
				HStack(spacing: 6) {
					formatBadge(row.outputFormat)
					Text(row.outputFilename)
						.lineLimit(1)
				}
			}
			.width(min: 200)

			TableColumn("Before") { row in
				Text(formatBytes(row.originalSize))
					.monospacedDigit()
			}
			.width(80)

			TableColumn("After") { row in
				Text(formatBytes(row.outputSize))
					.monospacedDigit()
			}
			.width(80)

			TableColumn("Saved") { row in
				HStack(spacing: 4) {
					Text("\(String(format: "%.1f", row.savingsPercent))%")
						.monospacedDigit()
						.foregroundStyle(row.savingsPercent > 0 ? Theme.success : Theme.error)
					if row.savingsPercent > 20 {
						Image(systemName: "arrow.down")
							.font(Theme.caption2)
							.foregroundStyle(Theme.success)
					}
				}
			}
			.width(80)

			TableColumn("Dimensions") { row in
				VStack(alignment: .leading, spacing: 1) {
					if let w = row.width, let h = row.height {
						Text("\(w) × \(h)")
							.monospacedDigit()
					} else {
						Text("—")
							.foregroundStyle(Theme.textSecondary)
					}
					if row.downscaledTo != nil {
						Text("downscaled")
							.font(Theme.caption2)
							.foregroundStyle(Theme.warning)
					}
				}
			}
			.width(110)

			TableColumn("Status") { row in
				if let error = row.error {
					Label(error, systemImage: "exclamationmark.circle")
						.foregroundStyle(Theme.error)
						.lineLimit(1)
				} else if row.targetMet == false {
					Label("target not met", systemImage: "exclamationmark.triangle.fill")
						.font(Theme.caption)
						.foregroundStyle(Theme.warning)
						.lineLimit(1)
				} else {
					Image(systemName: "checkmark.circle.fill")
						.foregroundStyle(Theme.success)
				}
			}
			.width(120)
		}
	}

	// MARK: - Empty State

	private var emptyState: some View {
		VStack(spacing: Theme.spacing) {
			Image(systemName: "chart.bar.doc.horizontal")
				.font(.system(size: 48))
				.foregroundStyle(Theme.textSecondary.opacity(0.5))
			Text("No results yet")
				.font(Theme.title3)
				.foregroundStyle(Theme.textSecondary)
			Text("Process some images to see the summary here")
				.font(Theme.callout)
				.foregroundStyle(Theme.textSecondary)
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
	}

	// MARK: - Helpers

	private var flattenedResults: [ResultRow] {
		appState.results.flatMap { result -> [ResultRow] in
			if result.isSuccess {
				return result.outputFiles.map { output in
					ResultRow(
						id: output.id,
						outputFilename: output.filename,
						outputFormat: output.format,
						originalSize: output.originalSize,
						outputSize: output.fileSize,
						savingsPercent: output.savingsPercent,
						width: output.width,
						height: output.height,
						error: output.error,
						targetMet: output.targetMet,
						downscaledTo: output.downscaledTo
					)
				}
			} else {
				return [ResultRow(
					id: result.id,
					outputFilename: result.sourceFile.filename,
					outputFormat: result.sourceFile.format,
					originalSize: result.sourceFile.originalSize,
					outputSize: 0,
					savingsPercent: 0,
					width: nil,
					height: nil,
					error: result.error,
					targetMet: nil,
					downscaledTo: nil
				)]
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

// MARK: - Row Model

private struct ResultRow: Identifiable {
	let id: UUID
	let outputFilename: String
	let outputFormat: ImageFormat
	let originalSize: Int64
	let outputSize: Int64
	let savingsPercent: Double
	let width: Int?
	let height: Int?
	let error: String?
	let targetMet: Bool?
	let downscaledTo: String?
}
