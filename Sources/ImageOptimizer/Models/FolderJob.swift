import Foundation

/// The per-folder overridable subset of processing config. Each folder added in the
/// Folders tab carries its own `FolderCompression`; everything else (encoder tuning,
/// file patterns, recursive/skip, rename) stays global on `ProcessingSettings`.
struct FolderCompression: Equatable {
	var compressionMode: CompressionMode
	var quality: Int
	var targetSizes: TargetSizes
	var allowDownscaleToTarget: Bool
	var keepSourceFormat: Bool
	var outputFormats: Set<ImageFormat>
	var maxDimension: Int?
	var resizeMode: ResizeMode

	/// Seed from the current global defaults.
	init(from s: ProcessingSettings) {
		compressionMode = s.compressionMode
		quality = s.quality
		targetSizes = s.targetSizes
		allowDownscaleToTarget = s.allowDownscaleToTarget
		keepSourceFormat = s.keepSourceFormat
		outputFormats = s.outputFormats
		maxDimension = s.maxDimension
		resizeMode = s.resizeMode
	}

	/// Formats this folder emits, in display order (source first if kept).
	var formatList: String {
		var names: [String] = []
		if keepSourceFormat { names.append("source") }
		for f in ImageFormat.allCases where outputFormats.contains(f) { names.append(f.rawValue) }
		return names.isEmpty ? "source" : names.joined(separator: "+")
	}

	/// One-line summary shown on the collapsed folder row.
	var summary: String {
		var parts: [String]
		switch compressionMode {
		case .quality:
			parts = ["Quality \(quality)"]
		case .targetSize:
			parts = ["Target"]
		}
		parts.append(formatList)
		if let maxDim = maxDimension { parts.append("≤\(maxDim)px") }
		return parts.joined(separator: " · ")
	}
}

/// A folder queued in the Folders tab, with its own independent job config.
struct FolderJob: Identifiable, Equatable {
	let id = UUID()
	var url: URL
	var config: FolderCompression
}

extension ProcessingSettings {
	/// View the global defaults as a `FolderCompression`, or apply one back.
	var compression: FolderCompression {
		get { FolderCompression(from: self) }
		set {
			compressionMode = newValue.compressionMode
			quality = newValue.quality
			targetSizes = newValue.targetSizes
			allowDownscaleToTarget = newValue.allowDownscaleToTarget
			keepSourceFormat = newValue.keepSourceFormat
			outputFormats = newValue.outputFormats
			maxDimension = newValue.maxDimension
			resizeMode = newValue.resizeMode
		}
	}

	/// A copy of these (global) settings with a folder's per-folder overrides applied.
	func applying(_ c: FolderCompression) -> ProcessingSettings {
		var s = self
		s.compression = c
		return s
	}
}
