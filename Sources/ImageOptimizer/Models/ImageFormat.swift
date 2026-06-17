import Foundation

/// Supported image formats for input and output
enum ImageFormat: String, CaseIterable, Identifiable, Codable {
	case jpeg = "JPEG"
	case png = "PNG"
	case webp = "WebP"
	case avif = "AVIF"

	var id: String { rawValue }

	var fileExtensions: [String] {
		switch self {
		case .jpeg: return ["jpg", "jpeg"]
		case .png: return ["png"]
		case .webp: return ["webp"]
		case .avif: return ["avif"]
		}
	}

	var primaryExtension: String {
		switch self {
		case .jpeg: return "jpg"
		case .png: return "png"
		case .webp: return "webp"
		case .avif: return "avif"
		}
	}

	static func from(extension ext: String) -> ImageFormat? {
		let lower = ext.lowercased()
		return allCases.first { $0.fileExtensions.contains(lower) }
	}
}
