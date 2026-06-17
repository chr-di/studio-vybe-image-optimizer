import Foundation
import CoreImage
import ImageIO
import AppKit

/// Handles encoding/decoding and optimization of individual images.
/// Uses macOS native APIs (ImageIO, Core Image, vImage) where possible,
/// and shells out to CLI tools (pngquant, oxipng, cwebp, avifenc) for
/// formats/quality not supported natively.
///
/// Two compression modes:
/// - `.quality`: encode at a single mapped quality (original behaviour).
/// - `.targetSize`: binary-search encoder quality (and PNG colour count) to land
///   just under a per-format byte budget; if min quality still overshoots and
///   downscaling is allowed, progressively shrink dimensions until it fits.
final class ImageProcessor {

	// MARK: - Public API

	/// Process a single image file according to settings.
	/// Returns array of output files (PNG inputs produce multiple outputs).
	static func process(
		file: ImageFile,
		settings: ProcessingSettings,
		rename: RenameSettings,
		fileIndex: Int,
		dryRun: Bool,
		outputDirectoryOverride: URL? = nil
	) throws -> [OutputFile] {
		// Load source image
		guard let imageSource = CGImageSourceCreateWithURL(file.url as CFURL, nil),
			  let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
			throw ProcessingError.failedToLoadImage(file.filename)
		}

		// Resize if needed (manual resize from settings — independent of target-size downscaling)
		let resized = resizeIfNeeded(cgImage, maxDimension: settings.maxDimension, mode: settings.resizeMode)
		let wasResized = resized !== cgImage
		let outputWidth = resized.width
		let outputHeight = resized.height

		// Determine output format(s)
		let outputFormats = determineOutputFormats(source: file, settings: settings)

		// Prepare output directory
		let outputDir = outputDirectoryOverride ?? file.outputDirectory
		if !dryRun {
			try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
		}

		// Generate output name
		let baseName = rename.enabled
			? rename.apply(to: file.nameWithoutExtension, index: fileIndex)
			: file.nameWithoutExtension

		let targetMode = settings.compressionMode == .targetSize

		var outputs: [OutputFile] = []

		for output in outputFormats {
			// Replace original base name with renamed base name in the output spec
			let outputName = output.name.replacingOccurrences(of: file.nameWithoutExtension, with: baseName)
			let outputURL = outputDir.appendingPathComponent("\(outputName).\(output.format.primaryExtension)")

			if dryRun {
				let estimate = targetMode
					? settings.targetSizes.bytes(for: output.format)
					: estimateSize(original: file.originalSize, format: output.format, settings: settings)
				outputs.append(OutputFile(
					url: outputURL, format: output.format, fileSize: estimate,
					width: outputWidth, height: outputHeight, originalSize: file.originalSize,
					targetMet: targetMode ? true : nil
				))
				continue
			}

			// --- Target-size mode ---
			if targetMode {
				do {
					let target = settings.targetSizes.bytes(for: output.format)
					let result = try encodeToTargetSize(
						image: resized, format: output.format, targetBytes: target,
						settings: settings, allowDownscale: settings.allowDownscaleToTarget, to: outputURL
					)
					outputs.append(OutputFile(
						url: outputURL, format: output.format, fileSize: fileSize(at: outputURL),
						width: result.width, height: result.height, originalSize: file.originalSize,
						targetMet: result.targetMet,
						downscaledTo: result.downscaled ? "\(result.width) × \(result.height)" : nil
					))
				} catch {
					outputs.append(OutputFile(
						url: outputURL, format: output.format, fileSize: 0,
						width: outputWidth, height: outputHeight, originalSize: file.originalSize,
						error: error.localizedDescription
					))
				}
				continue
			}

			// --- Quality mode (original behaviour) ---
			do {
				try encode(
					image: resized,
					to: outputURL,
					format: output.format,
					settings: settings,
					lossless: output.lossless,
					sourceFile: file,
					wasResized: wasResized
				)

				// Never make files larger: if output is same format and bigger, copy original
				let outputSize = fileSize(at: outputURL)
				if output.format == file.format && outputSize >= file.originalSize && settings.maxDimension == nil {
					try FileManager.default.removeItem(at: outputURL)
					try FileManager.default.copyItem(at: file.url, to: outputURL)
				}
			} catch {
				// Skip this output variant (e.g. cwebp not installed) — don't fail the whole file
				outputs.append(OutputFile(
					url: outputURL,
					format: output.format,
					fileSize: 0,
					width: outputWidth,
					height: outputHeight,
					originalSize: file.originalSize,
					error: error.localizedDescription
				))
				continue
			}

			outputs.append(OutputFile(
				url: outputURL,
				format: output.format,
				fileSize: fileSize(at: outputURL),
				width: outputWidth,
				height: outputHeight,
				originalSize: file.originalSize
			))
		}

		return outputs
	}

	// MARK: - Output Format Determination

	private struct OutputSpec {
		let name: String
		let format: ImageFormat
		let lossless: Bool
	}

	private static func determineOutputFormats(source: ImageFile, settings: ProcessingSettings) -> [OutputSpec] {
		let baseName = source.nameWithoutExtension
		let qualityMode = settings.compressionMode == .quality

		// Output set = source's own format (if kept) plus any explicitly chosen formats,
		// in canonical order, de-duplicated. Never produce nothing.
		var formats: [ImageFormat] = []
		if settings.keepSourceFormat { formats.append(source.format) }
		for f in ImageFormat.allCases where settings.outputFormats.contains(f) {
			if !formats.contains(f) { formats.append(f) }
		}
		if formats.isEmpty { formats = [source.format] }

		// Distinct extensions per format → distinct filenames. PNG is lossless in quality
		// mode; target mode sizes every format via encodeToTargetSize regardless of this flag.
		return formats.map { fmt in
			OutputSpec(name: baseName, format: fmt, lossless: qualityMode && fmt == .png)
		}
	}

	// MARK: - Target-Size Encoding

	struct TargetEncodeResult {
		let targetMet: Bool
		let downscaled: Bool
		let width: Int
		let height: Int
	}

	/// Encode `image` as `format` to land under `targetBytes`. Binary-searches the
	/// per-format quality ladder for the best (highest-quality) encode that fits; if
	/// nothing fits at the bottom of the ladder and `allowDownscale` is set, shrinks
	/// dimensions and retries. Writes the winner to `url`.
	static func encodeToTargetSize(
		image baseImage: CGImage,
		format: ImageFormat,
		targetBytes: Int64,
		settings: ProcessingSettings,
		allowDownscale: Bool,
		to url: URL
	) throws -> TargetEncodeResult {
		let fm = FileManager.default
		var working = baseImage
		var didDownscale = false

		for round in 0..<16 {
			let search = searchUnderTarget(image: working, format: format, targetBytes: targetBytes, settings: settings)

			// Found a candidate under the budget → ship the best one.
			if let bestURL = search.bestURL {
				try place(bestURL, at: url)
				if let s = search.smallestURL, s != bestURL { try? fm.removeItem(at: s) }
				return TargetEncodeResult(targetMet: true, downscaled: didDownscale,
										  width: working.width, height: working.height)
			}

			// Nothing fits. Decide whether to downscale and retry.
			let ref = max(search.smallestBytes, 1)
			var factor = (Double(targetBytes) / Double(ref)).squareRoot()
			factor = min(0.9, max(0.45, factor))   // shrink 10%–55% per round
			let newW = Int((Double(working.width) * factor).rounded())
			let newH = Int((Double(working.height) * factor).rounded())
			let canShrink = allowDownscale && round < 15
				&& newW < working.width && newH < working.height
				&& newW >= 16 && newH >= 16

			if canShrink, let scaled = resizeExact(working, width: newW, height: newH) {
				if let s = search.smallestURL { try? fm.removeItem(at: s) }
				working = scaled
				didDownscale = true
				continue
			}

			// Can't (or won't) shrink further — accept the smallest achievable, flag as not met.
			guard let smallestURL = search.smallestURL else {
				throw ProcessingError.failedToEncode(format.rawValue)
			}
			try place(smallestURL, at: url)
			let bytes = fileSize(at: url)
			return TargetEncodeResult(targetMet: bytes <= targetBytes, downscaled: didDownscale,
									  width: working.width, height: working.height)
		}

		throw ProcessingError.failedToEncode(format.rawValue)
	}

	private struct TargetSearch {
		let bestURL: URL?        // highest-quality encode ≤ target (nil if none fit)
		let smallestURL: URL?    // lowest-quality encode (for downscale estimate / fallback)
		let smallestBytes: Int64
	}

	/// Binary-search the quality ladder. Encodes are memoised so each ladder rung is
	/// rendered at most once. Temp files for non-winning rungs are cleaned up.
	private static func searchUnderTarget(
		image: CGImage, format: ImageFormat, targetBytes: Int64, settings: ProcessingSettings
	) -> TargetSearch {
		let fm = FileManager.default
		let levels = paramLevels(for: format)
		var cache: [Int: (url: URL, bytes: Int64)] = [:]

		func encode(_ i: Int) -> (url: URL, bytes: Int64)? {
			if let c = cache[i] { return c }
			let out = fm.temporaryDirectory
				.appendingPathComponent("tgt-\(UUID().uuidString).\(format.primaryExtension)")
			guard encodeAtParam(image: image, format: format, param: levels[i], settings: settings, to: out),
				  fm.fileExists(atPath: out.path) else { return nil }
			let entry = (url: out, bytes: fileSize(at: out))
			cache[i] = entry
			return entry
		}

		var bestIdx: Int? = nil
		var lo = 0, hi = levels.count - 1
		while lo <= hi {
			let mid = (lo + hi) / 2
			if let entry = encode(mid) {
				if entry.bytes <= targetBytes { bestIdx = mid; lo = mid + 1 }
				else { hi = mid - 1 }
			} else {
				// Encoder unavailable at this rung (e.g. pngquant missing) — treat as "too big".
				hi = mid - 1
			}
		}

		let smallest = encode(0)
		let bestURL = bestIdx.flatMap { cache[$0]?.url }

		// Clean up everything except the winner and the smallest.
		let keep = Set([bestURL?.path, smallest?.url.path].compactMap { $0 })
		for (_, entry) in cache where !keep.contains(entry.url.path) {
			try? fm.removeItem(at: entry.url)
		}

		return TargetSearch(bestURL: bestURL, smallestURL: smallest?.url, smallestBytes: smallest?.bytes ?? Int64.max)
	}

	/// Quality ladders, ascending by resulting file size (so binary search is monotonic).
	private static func paramLevels(for format: ImageFormat) -> [Int] {
		switch format {
		case .jpeg: return [20, 25, 30, 35, 40, 45, 50, 55, 60, 65, 70, 75, 80, 85, 90, 95]
		case .webp: return [10, 20, 30, 40, 50, 55, 60, 65, 70, 75, 80, 85, 90, 95]
		case .avif: return [62, 56, 50, 44, 38, 32, 26, 20]   // CQ values; lower CQ → bigger file
		case .png:
			// pngquant colour ladder (small → 256), then lossless (-1) as the largest rung.
			return pngquantAvailable
				? [2, 3, 4, 6, 8, 12, 16, 24, 32, 48, 64, 96, 128, 192, 256, -1]
				: [-1]
		}
	}

	private static func encodeAtParam(image: CGImage, format: ImageFormat, param: Int, settings: ProcessingSettings, to url: URL) -> Bool {
		switch format {
		case .jpeg: return writeJPEG(image: image, to: url, quality: param, progressive: settings.jpeg.progressive)
		case .webp: return writeWebP(image: image, to: url, quality: param)
		case .avif: return writeAVIF(image: image, to: url, cq: param)
		case .png:  return param == -1
			? writePNGLossless(image: image, to: url)
			: writePNGQuantized(image: image, to: url, colors: param)
		}
	}

	private static func place(_ src: URL, at dest: URL) throws {
		let fm = FileManager.default
		if fm.fileExists(atPath: dest.path) { try? fm.removeItem(at: dest) }
		try fm.moveItem(at: src, to: dest)
	}

	// MARK: - Explicit-quality writers (used by target-size mode)

	/// Lossy JPEG at an explicit quality: Jpegli → MozJPEG → ImageIO.
	private static func writeJPEG(image: CGImage, to url: URL, quality: Int, progressive: Bool) -> Bool {
		if encodeJPEGViaJpegli(image: image, to: url, quality: quality, progressive: progressive) { return true }
		if encodeJPEGViaMozJPEG(image: image, to: url, quality: quality, progressive: progressive) { return true }
		return imageIOWriteJPEG(image: image, to: url, quality: quality, progressive: progressive)
	}

	private static func writeWebP(image: CGImage, to url: URL, quality: Int) -> Bool {
		// Native ImageIO first
		if let dest = CGImageDestinationCreateWithURL(url as CFURL, "org.webmproject.webp" as CFString, 1, nil) {
			let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: Double(quality) / 100.0]
			CGImageDestinationAddImage(dest, image, options as CFDictionary)
			if CGImageDestinationFinalize(dest) { return true }
		}
		// Fallback: cwebp via temp PNG
		guard let tempPNG = writeTempPNG(image) else { return false }
		defer { try? FileManager.default.removeItem(at: tempPNG) }
		return (try? runCLITool("cwebp", arguments: ["-q", "\(quality)", "-m", "4", tempPNG.path, "-o", url.path], required: true)) != nil
	}

	private static func writeAVIF(image: CGImage, to url: URL, cq: Int) -> Bool {
		// Native ImageIO (normalize CQ → 0...1 quality, lower CQ = higher quality)
		if let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.avif" as CFString, 1, nil) {
			let normalized = max(0, min(1.0, 1.0 - (Double(cq) / 63.0)))
			let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: normalized]
			CGImageDestinationAddImage(dest, image, options as CFDictionary)
			if CGImageDestinationFinalize(dest) { return true }
		}
		// Fallback: avifenc via temp PNG
		guard let tempPNG = writeTempPNG(image) else { return false }
		defer { try? FileManager.default.removeItem(at: tempPNG) }
		let speed = max(0, min(10, 10 - 4))
		return (try? runCLITool("avifenc", arguments: [
			"--min", "\(cq)", "--max", "\(cq)", "--speed", "\(speed)", tempPNG.path, url.path
		], required: true)) != nil
	}

	/// Lossy PNG via pngquant colour quantization, then oxipng recompression (if present).
	private static func writePNGQuantized(image: CGImage, to url: URL, colors: Int) -> Bool {
		guard let pngquant = toolPath("pngquant") else { return false }
		guard let tempPNG = writeTempPNG(image) else { return false }
		defer { try? FileManager.default.removeItem(at: tempPNG) }

		let n = max(2, min(256, colors))
		let process = Process()
		process.executableURL = URL(fileURLWithPath: pngquant)
		process.arguments = ["\(n)", "--force", "--output", url.path, tempPNG.path]
		process.standardOutput = FileHandle.nullDevice
		process.standardError = FileHandle.nullDevice
		do {
			try process.run()
			process.waitUntilExit()
			guard process.terminationStatus == 0 else { return false }
		} catch {
			return false
		}
		// Optional lossless squeeze on top
		try? runCLITool("oxipng", arguments: ["-o", "2", "--strip", "safe", url.path])
		return FileManager.default.fileExists(atPath: url.path)
	}

	/// Lossless optimized PNG (ImageIO → oxipng if present). Always succeeds.
	private static func writePNGLossless(image: CGImage, to url: URL) -> Bool {
		guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return false }
		CGImageDestinationAddImage(dest, image, nil)
		guard CGImageDestinationFinalize(dest) else { return false }
		try? runCLITool("oxipng", arguments: ["-o", "2", "--strip", "safe", url.path])
		return true
	}

	private static func imageIOWriteJPEG(image: CGImage, to url: URL, quality: Int, progressive: Bool) -> Bool {
		guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil) else { return false }
		var options: [CFString: Any] = [
			kCGImageDestinationLossyCompressionQuality: Double(quality) / 100.0,
		]
		if progressive { options[kCGImagePropertyJFIFIsProgressive] = true }
		CGImageDestinationAddImage(dest, image, options as CFDictionary)
		return CGImageDestinationFinalize(dest)
	}

	private static func writeTempPNG(_ image: CGImage) -> URL? {
		let tempPNG = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
		guard let dest = CGImageDestinationCreateWithURL(tempPNG as CFURL, "public.png" as CFString, 1, nil) else { return nil }
		CGImageDestinationAddImage(dest, image, nil)
		guard CGImageDestinationFinalize(dest) else { return nil }
		return tempPNG
	}

	// MARK: - Encoding (quality mode)

	private static func encode(
		image: CGImage,
		to url: URL,
		format: ImageFormat,
		settings: ProcessingSettings,
		lossless: Bool,
		sourceFile: ImageFile? = nil,
		wasResized: Bool = true
	) throws {
		switch format {
		case .jpeg:
			try encodeJPEG(image: image, to: url, settings: settings, sourceFile: sourceFile, wasResized: wasResized)
		case .png:
			try encodePNG(image: image, to: url, settings: settings)
		case .webp:
			try encodeWebP(image: image, to: url, settings: settings, lossless: lossless)
		case .avif:
			try encodeAVIF(image: image, to: url, settings: settings)
		}
	}

	private static func encodeJPEG(image: CGImage, to url: URL, settings: ProcessingSettings, sourceFile: ImageFile? = nil, wasResized: Bool = true) throws {
		let quality = settings.effectiveQuality(for: .jpeg)
		let progressive = settings.jpeg.progressive

		// For JPEG→JPEG with no resize: try both lossless (jpegtran) and lossy (cjpeg),
		// keep whichever produces the smaller file.
		if let source = sourceFile, source.format == .jpeg, !wasResized {
			let fm = FileManager.default
			let tmpDir = fm.temporaryDirectory
			var candidates: [URL] = []

			// Candidate 1: jpegtran (lossless — progressive, optimize Huffman, strip metadata)
			let jpegtranOut = tmpDir.appendingPathComponent(UUID().uuidString + "-jpegtran.jpg")
			if optimizeJPEGViaJpegtran(source: source.url, to: jpegtranOut, settings: settings) {
				candidates.append(jpegtranOut)
			}

			// Candidate 2: lossy re-encode via Jpegli or MozJPEG
			let cjpegOut = tmpDir.appendingPathComponent(UUID().uuidString + "-cjpeg.jpg")
			if encodeJPEGViaJpegli(image: image, to: cjpegOut, quality: quality, progressive: progressive)
				|| encodeJPEGViaMozJPEG(image: image, to: cjpegOut, quality: quality, progressive: progressive) {
				candidates.append(cjpegOut)
			}

			if !candidates.isEmpty {
				let best = candidates.min(by: { fileSize(at: $0) < fileSize(at: $1) })!
				try fm.moveItem(at: best, to: url)
				for candidate in candidates where candidate != best {
					try? fm.removeItem(at: candidate)
				}
				return
			}
			// No CLI tools available — fall through to ImageIO
		} else {
			// Resize applied or source isn't JPEG — lossy re-encode only
			if encodeJPEGViaJpegli(image: image, to: url, quality: quality, progressive: progressive) { return }
			if encodeJPEGViaMozJPEG(image: image, to: url, quality: quality, progressive: progressive) { return }
		}

		// Fallback: native ImageIO (libjpeg-based)
		guard imageIOWriteJPEG(image: image, to: url, quality: quality, progressive: progressive) else {
			throw ProcessingError.failedToEncode("JPEG")
		}
	}

	/// Encode JPEG via MozJPEG's cjpeg at an explicit quality.
	private static func encodeJPEGViaMozJPEG(image: CGImage, to url: URL, quality: Int, progressive: Bool) -> Bool {
		let searchPaths = [
			"/opt/homebrew/opt/mozjpeg/bin/cjpeg",
			"/usr/local/opt/mozjpeg/bin/cjpeg",
		]
		guard let cjpegPath = searchPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
			return false
		}

		// Write temp PNG for cjpeg input (MozJPEG supports JPEG, PNG, BMP — NOT TIFF)
		guard let tempPNG = writeTempPNG(image) else { return false }
		defer { try? FileManager.default.removeItem(at: tempPNG) }

		var args = ["-quality", "\(quality)", "-optimize"]
		if progressive { args.append("-progressive") }
		args += ["-outfile", url.path, tempPNG.path]

		let process = Process()
		process.executableURL = URL(fileURLWithPath: cjpegPath)
		process.arguments = args
		process.standardOutput = FileHandle.nullDevice
		process.standardError = FileHandle.nullDevice

		do {
			try process.run()
			process.waitUntilExit()
			return process.terminationStatus == 0
		} catch {
			return false
		}
	}

	/// Encode JPEG via Google's Jpegli at an explicit quality.
	private static func encodeJPEGViaJpegli(image: CGImage, to url: URL, quality: Int, progressive: Bool) -> Bool {
		let searchPaths = [
			"/opt/homebrew/bin/cjpegli",
			"/usr/local/bin/cjpegli",
			"/opt/homebrew/opt/jpeg-xl/bin/cjpegli",
			"/usr/local/opt/jpeg-xl/bin/cjpegli",
		]
		guard let cjpegliPath = searchPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
			return false
		}

		guard let tempPNG = writeTempPNG(image) else { return false }
		defer { try? FileManager.default.removeItem(at: tempPNG) }

		var args = [tempPNG.path, url.path, "-q", "\(quality)"]
		if progressive { args += ["--progressive_level", "2"] }

		let process = Process()
		process.executableURL = URL(fileURLWithPath: cjpegliPath)
		process.arguments = args
		process.standardOutput = FileHandle.nullDevice
		process.standardError = FileHandle.nullDevice

		do {
			try process.run()
			process.waitUntilExit()
			return process.terminationStatus == 0
		} catch {
			return false
		}
	}

	/// Lossless JPEG optimization via MozJPEG's jpegtran (no quality param).
	private static func optimizeJPEGViaJpegtran(source: URL, to url: URL, settings: ProcessingSettings) -> Bool {
		let searchPaths = [
			"/opt/homebrew/opt/mozjpeg/bin/jpegtran",
			"/usr/local/opt/mozjpeg/bin/jpegtran",
		]
		guard let jpegtranPath = searchPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
			return false
		}

		var args = ["-optimize", "-copy", "none", "-outfile", url.path]
		if settings.jpeg.progressive { args.insert("-progressive", at: 0) }
		args.append(source.path)

		let process = Process()
		process.executableURL = URL(fileURLWithPath: jpegtranPath)
		process.arguments = args
		process.standardOutput = FileHandle.nullDevice
		process.standardError = FileHandle.nullDevice

		do {
			try process.run()
			process.waitUntilExit()
			return process.terminationStatus == 0
		} catch {
			return false
		}
	}

	private static func encodePNG(image: CGImage, to url: URL, settings: ProcessingSettings) throws {
		// Write initial PNG via ImageIO
		guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
			throw ProcessingError.failedToCreateEncoder("PNG")
		}
		CGImageDestinationAddImage(dest, image, nil)
		guard CGImageDestinationFinalize(dest) else {
			throw ProcessingError.failedToEncode("PNG")
		}

		// Post-process with CLI tools for smaller output
		switch settings.png.engine {
		case .pngquantOxipng:
			try runCLITool("pngquant", arguments: ["--force", "--output", url.path, "--quality=65-80", "--skip-if-larger", url.path])
			try runCLITool("oxipng", arguments: ["-o", "3", "--strip", "safe", url.path])
		case .oxipng:
			try runCLITool("oxipng", arguments: ["-o", "3", "--strip", "safe", url.path])
		case .zopflipng:
			try runCLITool("zopflipng", arguments: ["-y", "--iterations=15", url.path, url.path])
		}
	}

	private static func encodeWebP(image: CGImage, to url: URL, settings: ProcessingSettings, lossless: Bool) throws {
		// macOS 14+ supports WebP writing via ImageIO
		guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "org.webmproject.webp" as CFString, 1, nil) else {
			// Fallback: write temp PNG and convert via cwebp
			try encodeWebPViaCLI(image: image, to: url, settings: settings, lossless: lossless)
			return
		}
		var options: [CFString: Any] = [:]
		if lossless {
			options[kCGImageDestinationLossyCompressionQuality] = 1.0
		} else {
			let quality = Double(settings.effectiveQuality(for: .webp)) / 100.0
			options[kCGImageDestinationLossyCompressionQuality] = quality
		}
		CGImageDestinationAddImage(dest, image, options as CFDictionary)
		guard CGImageDestinationFinalize(dest) else {
			throw ProcessingError.failedToEncode("WebP")
		}
	}

	private static func encodeWebPViaCLI(image: CGImage, to url: URL, settings: ProcessingSettings, lossless: Bool) throws {
		guard let tempPNG = writeTempPNG(image) else {
			throw ProcessingError.failedToCreateEncoder("WebP (temp PNG)")
		}
		defer { try? FileManager.default.removeItem(at: tempPNG) }

		var args: [String]
		if lossless {
			args = ["-lossless", "-z", "6", tempPNG.path, "-o", url.path]
		} else {
			let q = settings.effectiveQuality(for: .webp)
			args = ["-q", "\(q)", "-m", "\(settings.webp.effort)", tempPNG.path, "-o", url.path]
		}
		try runCLITool("cwebp", arguments: args, required: true)
	}

	private static func encodeAVIF(image: CGImage, to url: URL, settings: ProcessingSettings) throws {
		// Try native ImageIO AVIF encoding first (macOS 14+)
		if let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.avif" as CFString, 1, nil) {
			let quality = Double(settings.effectiveQuality(for: .avif))
			let normalizedQuality = max(0, min(1.0, 1.0 - (quality / 63.0)))
			let options: [CFString: Any] = [
				kCGImageDestinationLossyCompressionQuality: normalizedQuality,
			]
			CGImageDestinationAddImage(dest, image, options as CFDictionary)
			if CGImageDestinationFinalize(dest) {
				return
			}
		}

		// Fallback: write temp PNG, encode via avifenc CLI
		guard let tempPNG = writeTempPNG(image) else {
			throw ProcessingError.failedToCreateEncoder("AVIF (temp PNG)")
		}
		defer { try? FileManager.default.removeItem(at: tempPNG) }

		let cq = settings.effectiveQuality(for: .avif)
		let speed = max(0, min(10, 10 - settings.avif.effort))
		try runCLITool("avifenc", arguments: [
			"--min", "\(cq)", "--max", "\(cq)",
			"--speed", "\(speed)",
			tempPNG.path, url.path
		], required: true)
	}

	// MARK: - Resize

	private static func resizeIfNeeded(_ image: CGImage, maxDimension: Int?, mode: ResizeMode = .longestSide) -> CGImage {
		guard let maxDim = maxDimension else { return image }
		let w = image.width
		let h = image.height

		let constrainedDimension: Int
		switch mode {
		case .longestSide: constrainedDimension = max(w, h)
		case .width: constrainedDimension = w
		case .height: constrainedDimension = h
		}

		guard constrainedDimension > maxDim else { return image }

		let scale = Double(maxDim) / Double(constrainedDimension)
		let newW = Int(Double(w) * scale)
		let newH = Int(Double(h) * scale)

		return resizeExact(image, width: newW, height: newH) ?? image
	}

	/// Resample to exact pixel dimensions using a robust sRGB 8-bit context.
	private static func resizeExact(_ image: CGImage, width newW: Int, height newH: Int) -> CGImage? {
		guard newW > 0, newH > 0 else { return nil }
		let colorSpace = CGColorSpaceCreateDeviceRGB()
		let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
		guard let context = CGContext(
			data: nil,
			width: newW,
			height: newH,
			bitsPerComponent: 8,
			bytesPerRow: 0,
			space: colorSpace,
			bitmapInfo: bitmapInfo
		) else { return nil }

		context.interpolationQuality = .high
		context.draw(image, in: CGRect(x: 0, y: 0, width: newW, height: newH))
		return context.makeImage()
	}

	// MARK: - CLI Tool Execution

	private static let toolSearchRoots = [
		"/opt/homebrew/bin",
		"/usr/local/bin",
		"/opt/homebrew/opt/zopfli/bin",
		"/usr/local/opt/zopfli/bin",
		"/usr/bin",
	]

	/// Resolve a CLI tool to its absolute path, searching common Homebrew/keg locations.
	static func toolPath(_ tool: String) -> String? {
		let candidates = toolSearchRoots.map { "\($0)/\(tool)" }
			+ ["/opt/homebrew/opt/\(tool)/bin/\(tool)", "/usr/local/opt/\(tool)/bin/\(tool)"]
		return candidates.first { FileManager.default.fileExists(atPath: $0) }
	}

	static var pngquantAvailable: Bool { toolPath("pngquant") != nil }

	private static func runCLITool(_ tool: String, arguments: [String], required: Bool = false) throws {
		guard let toolPath = toolPath(tool) else {
			if required {
				throw ProcessingError.cliToolNotFound(tool)
			}
			// Tool not installed — skip silently (optional post-processing)
			return
		}

		let process = Process()
		process.executableURL = URL(fileURLWithPath: toolPath)
		process.arguments = arguments
		process.standardOutput = FileHandle.nullDevice
		process.standardError = FileHandle.nullDevice

		try process.run()
		process.waitUntilExit()

		if process.terminationStatus != 0 {
			throw ProcessingError.cliToolFailed(tool, process.terminationStatus)
		}
	}

	// MARK: - Helpers

	private static func fileSize(at url: URL) -> Int64 {
		(try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
	}

	private static func estimateSize(original: Int64, format: ImageFormat, settings: ProcessingSettings) -> Int64 {
		let ratio: Double
		switch format {
		case .jpeg: ratio = 0.7
		case .png: ratio = 0.85
		case .webp: ratio = 0.5
		case .avif: ratio = 0.4
		}
		return Int64(Double(original) * ratio)
	}
}

// MARK: - Errors

enum ProcessingError: LocalizedError {
	case failedToLoadImage(String)
	case failedToCreateEncoder(String)
	case failedToEncode(String)
	case cliToolFailed(String, Int32)
	case cliToolNotFound(String)

	var errorDescription: String? {
		switch self {
		case .failedToLoadImage(let name): return "Failed to load image: \(name)"
		case .failedToCreateEncoder(let fmt): return "Failed to create \(fmt) encoder"
		case .failedToEncode(let fmt): return "Failed to encode \(fmt)"
		case .cliToolFailed(let tool, let code): return "\(tool) exited with code \(code)"
		case .cliToolNotFound(let tool): return "\(tool) not installed (brew install \(tool))"
		}
	}
}
