import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Scans directories for image files matching filter criteria
final class FileScanner {

	/// Scan one or more directories for image files
	/// - Parameters:
	///   - urls: Root directories to scan
	///   - recursive: Whether to scan subdirectories
	///   - includePatterns: Glob patterns to include (e.g. "*.jpg", "*.png")
	///   - excludePatterns: Glob patterns to exclude
	/// - Returns: Array of discovered ImageFile objects
	static func scan(
		directories urls: [URL],
		recursive: Bool,
		includePatterns: [String],
		excludePatterns: [String]
	) -> [ImageFile] {
		var results: [ImageFile] = []

		for rootURL in urls {
			let options: FileManager.DirectoryEnumerationOptions = recursive
				? [.skipsHiddenFiles]
				: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]

			guard let enumerator = FileManager.default.enumerator(
				at: rootURL,
				includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
				options: options
			) else { continue }

			for case let fileURL as URL in enumerator {
				// Skip files inside any "optimized" subfolder
				if fileURL.pathComponents.contains("optimized") { continue }

				guard let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
					  resourceValues.isRegularFile == true else { continue }

				let ext = fileURL.pathExtension.lowercased()
				guard let format = ImageFormat.from(extension: ext) else { continue }

				// Check include patterns
				let filename = fileURL.lastPathComponent
				if !includePatterns.isEmpty {
					let matches = includePatterns.contains { matchesGlob(filename: filename, pattern: $0) }
					if !matches { continue }
				}

				// Check exclude patterns
				if excludePatterns.contains(where: { matchesGlob(filename: filename, pattern: $0) }) {
					continue
				}

				let relativePath = fileURL.path.replacingOccurrences(of: rootURL.path + "/", with: "")
				let size = Int64(resourceValues.fileSize ?? 0)
				let dimensions = Self.imageDimensions(for: fileURL)

				results.append(ImageFile(
					url: fileURL,
					relativePath: relativePath,
					format: format,
					originalSize: size,
					width: dimensions?.width,
					height: dimensions?.height
				))
			}
		}

		return results.sorted { $0.relativePath < $1.relativePath }
	}

	/// Simple glob matching (supports * wildcard only)
	private static func matchesGlob(filename: String, pattern: String) -> Bool {
		let regexPattern = "^" + NSRegularExpression.escapedPattern(for: pattern)
			.replacingOccurrences(of: "\\*", with: ".*") + "$"
		return filename.range(of: regexPattern, options: [.regularExpression, .caseInsensitive]) != nil
	}

	/// Read image dimensions without loading full image data
	private static func imageDimensions(for url: URL) -> (width: Int, height: Int)? {
		guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
			  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
			  let width = properties[kCGImagePropertyPixelWidth] as? Int,
			  let height = properties[kCGImagePropertyPixelHeight] as? Int else {
			return nil
		}
		return (width, height)
	}
}
