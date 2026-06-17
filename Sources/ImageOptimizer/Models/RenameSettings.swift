import Foundation

/// Bulk rename mode
enum RenameMode: String, CaseIterable, Identifiable, Codable {
	case prefixSuffix = "Prefix / Suffix"
	case findReplace = "Find & Replace"
	case regex = "Regex Replace"
	case sequential = "Sequential Numbering"

	var id: String { rawValue }
}

/// Configuration for bulk renaming output files
struct RenameSettings: Codable, Equatable {
	var enabled: Bool = false
	var mode: RenameMode = .prefixSuffix

	// Prefix/Suffix mode
	var prefix: String = ""
	var suffix: String = ""

	// Find & Replace mode
	var findText: String = ""
	var replaceText: String = ""

	// Regex mode
	var regexPattern: String = ""
	var regexReplacement: String = ""

	// Sequential mode
	var sequentialTemplate: String = "IMG_{n}"
	var sequentialPadding: Int = 3
	var sequentialStart: Int = 1

	/// Apply the rename to a filename (without extension)
	func apply(to name: String, index: Int) -> String {
		guard enabled else { return name }

		switch mode {
		case .prefixSuffix:
			return "\(prefix)\(name)\(suffix)"

		case .findReplace:
			return name.replacingOccurrences(of: findText, with: replaceText)

		case .regex:
			guard let regex = try? NSRegularExpression(pattern: regexPattern) else {
				return name
			}
			let range = NSRange(name.startIndex..., in: name)
			return regex.stringByReplacingMatches(in: name, range: range, withTemplate: regexReplacement)

		case .sequential:
			let number = String(format: "%0\(sequentialPadding)d", sequentialStart + index)
			return sequentialTemplate.replacingOccurrences(of: "{n}", with: number)
		}
	}
}
