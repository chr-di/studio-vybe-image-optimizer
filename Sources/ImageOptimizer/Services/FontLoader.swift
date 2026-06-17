import Foundation
import CoreText
import AppKit

/// Registers the bundled Inter font faces with CoreText at launch so SwiftUI's
/// `Font.custom("Inter", ...)` resolves. Fonts ship as static OTFs in
/// `Resources/Fonts`, copied into `Contents/Resources/Fonts` by build.sh.
enum FontLoader {
	private static var didRegister = false

	static func register() {
		guard !didRegister else { return }
		didRegister = true

		guard let fontsDir = locateFontsDirectory() else {
			NSLog("[FontLoader] Fonts directory not found — falling back to system font.")
			return
		}

		let urls = (try? FileManager.default.contentsOfDirectory(at: fontsDir, includingPropertiesForKeys: nil))?
			.filter { ["otf", "ttf"].contains($0.pathExtension.lowercased()) } ?? []

		for url in urls {
			var errorRef: Unmanaged<CFError>?
			let ok = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &errorRef)
			if !ok {
				// Already-registered is benign (e.g. relaunch in the same process); log others.
				let err = errorRef?.takeRetainedValue()
				let code = (err as Error?).map { ($0 as NSError).code } ?? -1
				if code != CTFontManagerError.alreadyRegistered.rawValue {
					NSLog("[FontLoader] Failed to register \(url.lastPathComponent): \(String(describing: err))")
				}
			}
		}
	}

	/// Search the likely locations for the bundled fonts: the built `.app`
	/// (Bundle.main/Resources/Fonts) first, then a dev fallback for `swift run`.
	private static func locateFontsDirectory() -> URL? {
		var candidates: [URL] = []

		if let res = Bundle.main.resourceURL {
			candidates.append(res.appendingPathComponent("Fonts", isDirectory: true))
		}
		candidates.append(
			Bundle.main.bundleURL
				.appendingPathComponent("Contents/Resources/Fonts", isDirectory: true)
		)

		// Dev fallback: when launched via `swift run`, the executable lives at
		// <pkg>/.build/debug/ImageOptimizer — the package root holds Resources/Fonts.
		let exe = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
		let pkgRoot = exe
			.deletingLastPathComponent() // debug
			.deletingLastPathComponent() // .build
			.deletingLastPathComponent() // <pkg>
		candidates.append(pkgRoot.appendingPathComponent("Resources/Fonts", isDirectory: true))

		return candidates.first { url in
			var isDir: ObjCBool = false
			return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
		}
	}
}
