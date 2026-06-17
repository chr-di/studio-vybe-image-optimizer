import Foundation

/// Quality presets for the slider
enum QualityPreset: String, CaseIterable, Identifiable {
	case high = "High"
	case balanced = "Balanced"
	case small = "Small"

	var id: String { rawValue }

	var value: Int {
		switch self {
		case .high: return 90
		case .balanced: return 80
		case .small: return 70
		}
	}
}

/// Per-format encoder settings
struct JPEGSettings: Codable, Equatable {
	var progressive: Bool = true
	var stripMetadata: Bool = true
}

struct PNGSettings: Codable, Equatable {
	var engine: PNGEngine = .pngquantOxipng

	enum PNGEngine: String, CaseIterable, Identifiable, Codable {
		case pngquantOxipng = "pngquant + oxipng"
		case oxipng = "oxipng (lossless)"
		case zopflipng = "zopflipng (max)"

		var id: String { rawValue }
	}
}

struct WebPSettings: Codable, Equatable {
	var lossy: Bool = true
	var effort: Int = 4 // 0-6
}

struct AVIFSettings: Codable, Equatable {
	var quality: Int = 30 // CQ value: lower = better quality
	var effort: Int = 4 // 0-10
}

/// How to constrain the resize
enum ResizeMode: String, CaseIterable, Identifiable, Codable {
	case longestSide = "Longest side"
	case width = "Width"
	case height = "Height"

	var id: String { rawValue }
}

/// Compression strategy: a fixed quality, or a per-format target file size.
enum CompressionMode: String, CaseIterable, Identifiable, Codable {
	case quality = "Quality"
	case targetSize = "Target size"

	var id: String { rawValue }
}

/// Per-format target file sizes (in kilobytes) used in `.targetSize` mode.
struct TargetSizes: Codable, Equatable {
	var jpegKB: Int = 200
	var pngKB:  Int = 300
	var webpKB: Int = 150
	var avifKB: Int = 100   // used only when an AVIF output is produced in target mode

	/// Target byte budget for a given output format.
	func bytes(for format: ImageFormat) -> Int64 {
		Int64(max(1, self[format])) * 1024
	}

	/// KB target per format, addressable by `ImageFormat` (get/set).
	subscript(format: ImageFormat) -> Int {
		get {
			switch format {
			case .jpeg: return jpegKB
			case .png:  return pngKB
			case .webp: return webpKB
			case .avif: return avifKB
			}
		}
		set {
			switch format {
			case .jpeg: jpegKB = newValue
			case .png:  pngKB = newValue
			case .webp: webpKB = newValue
			case .avif: avifKB = newValue
			}
		}
	}
}

/// Main processing configuration
struct ProcessingSettings: Codable, Equatable {
	var quality: Int = 60
	var compressionMode: CompressionMode = .quality
	var targetSizes: TargetSizes = TargetSizes()
	/// In target-size mode, allow downscaling dimensions when min quality still overshoots.
	var allowDownscaleToTarget: Bool = true
	/// Emit the source's own format (optimize in place), in addition to any `outputFormats`.
	var keepSourceFormat: Bool = true
	/// Extra formats to produce for every image (true conversion). Empty = source only.
	var outputFormats: Set<ImageFormat> = []
	var maxDimension: Int? = nil
	var resizeMode: ResizeMode = .longestSide
	var minimumQualityFloor: Int? = nil
	var skipAlreadyOptimized: Bool = true
	var recursive: Bool = false
	var includePatterns: [String] = ["*.jpg", "*.jpeg", "*.png", "*.webp"]
	var excludePatterns: [String] = []

	// Per-format settings
	var jpeg: JPEGSettings = JPEGSettings()
	var png: PNGSettings = PNGSettings()
	var webp: WebPSettings = WebPSettings()
	var avif: AVIFSettings = AVIFSettings()

	/// Map quality slider (1-100) to sane encoder range per format
	func effectiveQuality(for format: ImageFormat) -> Int {
		switch format {
		case .jpeg:
			// Map 1-100 → 70-92
			return 70 + Int(Double(quality) / 100.0 * 22.0)
		case .webp:
			// Map 1-100 → 65-85
			return 65 + Int(Double(quality) / 100.0 * 20.0)
		case .avif:
			// Map 1-100 → CQ 40-28 (inverted: lower CQ = better quality)
			return 40 - Int(Double(quality) / 100.0 * 12.0)
		case .png:
			// PNG is lossless, quality doesn't apply directly
			return quality
		}
	}
}
