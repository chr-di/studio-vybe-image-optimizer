import Foundation

/// Represents a single image file to process
struct ImageFile: Identifiable, Hashable {
	let id = UUID()
	let url: URL
	let relativePath: String
	let format: ImageFormat
	let originalSize: Int64
	let width: Int?
	let height: Int?

	var filename: String { url.lastPathComponent }
	var nameWithoutExtension: String { url.deletingPathExtension().lastPathComponent }
	var parentDirectory: URL { url.deletingLastPathComponent() }

	/// The output directory: always an `optimized/` subfolder inside the file's parent
	var outputDirectory: URL {
		parentDirectory.appendingPathComponent("optimized", isDirectory: true)
	}
}

/// Result of processing a single image
struct ProcessingResult: Identifiable {
	let id = UUID()
	let sourceFile: ImageFile
	let outputFiles: [OutputFile]
	let error: String?
	let processingTime: TimeInterval

	var totalSavedBytes: Int64 {
		outputFiles.reduce(0) { $0 + ($1.savedBytes) }
	}

	var isSuccess: Bool { error == nil }
}

/// A single output file produced from a source
struct OutputFile: Identifiable {
	let id = UUID()
	let url: URL
	let format: ImageFormat
	let fileSize: Int64
	let width: Int?
	let height: Int?
	let originalSize: Int64
	let error: String?

	/// Target-size mode: whether the per-format target byte budget was met.
	/// `nil` in quality mode (target not applicable).
	let targetMet: Bool?

	/// Target-size mode: set to "W × H" when the image had to be downscaled
	/// below its source dimensions to reach the target. `nil` if not downscaled.
	let downscaledTo: String?

	init(
		url: URL,
		format: ImageFormat,
		fileSize: Int64,
		width: Int?,
		height: Int?,
		originalSize: Int64,
		error: String? = nil,
		targetMet: Bool? = nil,
		downscaledTo: String? = nil
	) {
		self.url = url
		self.format = format
		self.fileSize = fileSize
		self.width = width
		self.height = height
		self.originalSize = originalSize
		self.error = error
		self.targetMet = targetMet
		self.downscaledTo = downscaledTo
	}

	var filename: String { url.lastPathComponent }

	var savedBytes: Int64 { originalSize - fileSize }

	var isSuccess: Bool { error == nil }

	var savingsPercent: Double {
		guard originalSize > 0, isSuccess else { return 0 }
		return Double(savedBytes) / Double(originalSize) * 100.0
	}
}
