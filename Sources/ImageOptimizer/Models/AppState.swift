import Foundation
import SwiftUI

/// Persisted watched folder configuration
struct WatchedFolder: Codable, Identifiable, Equatable {
	let id: UUID
	var url: URL
	var isEnabled: Bool
	var addedDate: Date
	var bookmarkData: Data?

	init(url: URL) {
		self.id = UUID()
		self.url = url
		self.isEnabled = true
		self.addedDate = Date()
		self.bookmarkData = try? url.bookmarkData(
			options: [.withSecurityScope],
			includingResourceValuesForKeys: nil,
			relativeTo: nil
		)
	}

	/// Resolve bookmark to get a security-scoped URL (persists access across launches)
	mutating func resolveBookmark() -> Bool {
		guard let data = bookmarkData else { return false }
		var isStale = false
		guard let resolved = try? URL(
			resolvingBookmarkData: data,
			options: [.withSecurityScope],
			relativeTo: nil,
			bookmarkDataIsStale: &isStale
		) else { return false }

		if isStale {
			bookmarkData = try? resolved.bookmarkData(
				options: [.withSecurityScope],
				includingResourceValuesForKeys: nil,
				relativeTo: nil
			)
		}
		url = resolved
		return resolved.startAccessingSecurityScopedResource()
	}
}

/// Central app state shared across views
final class AppState: ObservableObject {
	// MARK: - Input Configuration

	@Published var folderJobs: [FolderJob] = []
	@Published var settings: ProcessingSettings = ProcessingSettings()   // global defaults + shared options
	@Published var renameSettings: RenameSettings = RenameSettings()

	// MARK: - Scanned Files

	@Published var scannedFiles: [ImageFile] = []
	@Published var isScanning: Bool = false

	// MARK: - Processing State

	@Published var isProcessing: Bool = false
	@Published var isDryRun: Bool = false
	@Published var isPreviewMode: Bool = false
	@Published var processedCount: Int = 0
	@Published var totalCount: Int = 0
	@Published var results: [ProcessingResult] = []
	@Published var currentFile: String = ""

	// MARK: - Watch State

	@Published var watchedFolders: [WatchedFolder] = []
	@Published var watchAutoOptimize: Bool = true
	@Published var watchActivity: [WatchActivityEntry] = []

	// MARK: - Drop Output

	@Published var dropOutputFolder: URL? = nil
	private var dropOutputBookmarkData: Data? = nil

	// MARK: - UI State

	@Published var showSettings: Bool = false
	@Published var activeTab: SidebarTab = .watch

	// MARK: - Private

	private let folderWatcher = FolderWatcher()
	private var watcherTokens: [UUID: UUID] = [:]
	private var processedFilePaths: Set<String> = []

	var progress: Double {
		guard totalCount > 0 else { return 0 }
		return Double(processedCount) / Double(totalCount)
	}

	var totalOriginalSize: Int64 {
		scannedFiles.reduce(0) { $0 + $1.originalSize }
	}

	var totalOptimizedSize: Int64 {
		results.flatMap(\.outputFiles).reduce(0) { $0 + $1.fileSize }
	}

	var totalSavings: Int64 {
		totalOriginalSize - totalOptimizedSize
	}

	var savingsPercent: Double {
		guard totalOriginalSize > 0 else { return 0 }
		return Double(totalSavings) / Double(totalOriginalSize) * 100.0
	}

	// MARK: - Lifecycle

	func loadPersistedState() {
		if let data = UserDefaults.standard.data(forKey: "watchedFolders"),
		   var folders = try? JSONDecoder().decode([WatchedFolder].self, from: data) {
			// Resolve security-scoped bookmarks to regain file access
			for i in folders.indices {
				_ = folders[i].resolveBookmark()
			}
			watchedFolders = folders
		}
		watchAutoOptimize = UserDefaults.standard.object(forKey: "watchAutoOptimize") as? Bool ?? true

		// Restore drop output folder from bookmark
		if let bookmarkData = UserDefaults.standard.data(forKey: "dropOutputBookmark") {
			var isStale = false
			if let resolved = try? URL(
				resolvingBookmarkData: bookmarkData,
				options: [.withSecurityScope],
				relativeTo: nil,
				bookmarkDataIsStale: &isStale
			) {
				_ = resolved.startAccessingSecurityScopedResource()
				dropOutputFolder = resolved
				self.dropOutputBookmarkData = isStale
					? (try? resolved.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil))
					: bookmarkData
			}
		}

		for folder in watchedFolders where folder.isEnabled {
			startWatching(folder)
		}
	}

	private func saveWatchedFolders() {
		if let data = try? JSONEncoder().encode(watchedFolders) {
			UserDefaults.standard.set(data, forKey: "watchedFolders")
		}
		UserDefaults.standard.set(watchAutoOptimize, forKey: "watchAutoOptimize")
	}

	// MARK: - Drop Output Folder

	func setDropOutputFolder(_ url: URL) {
		dropOutputFolder = url
		dropOutputBookmarkData = try? url.bookmarkData(
			options: [.withSecurityScope],
			includingResourceValuesForKeys: nil,
			relativeTo: nil
		)
		UserDefaults.standard.set(dropOutputBookmarkData, forKey: "dropOutputBookmark")
	}

	func clearDropOutputFolder() {
		dropOutputFolder = nil
		dropOutputBookmarkData = nil
		UserDefaults.standard.removeObject(forKey: "dropOutputBookmark")
	}

	// MARK: - Manual Folder Actions

	func scanFolders() {
		guard !folderJobs.isEmpty else {
			scannedFiles = []
			return
		}

		isScanning = true
		scannedFiles = []
		results = []

		let folders = folderJobs.map(\.url)
		let recursive = settings.recursive
		let include = settings.includePatterns
		let exclude = settings.excludePatterns

		DispatchQueue.global(qos: .userInitiated).async {
			let files = FileScanner.scan(
				directories: folders,
				recursive: recursive,
				includePatterns: include,
				excludePatterns: exclude
			)

			DispatchQueue.main.async { [weak self] in
				self?.scannedFiles = files
				self?.isScanning = false
			}
		}
	}

	func startProcessing() {
		guard !scannedFiles.isEmpty else { return }

		isProcessing = true
		processedCount = 0
		results = []

		let filesToProcess = isPreviewMode ? Array(scannedFiles.prefix(10)) : scannedFiles
		let globalSettings = settings
		let jobs = folderJobs
		let rename = renameSettings
		let dryRun = isDryRun
		totalCount = filesToProcess.count

		DispatchQueue.global(qos: .userInitiated).async {
			for (index, file) in filesToProcess.enumerated() {
				DispatchQueue.main.async { [weak self] in
					self?.currentFile = file.filename
				}

				// Apply this file's owning-folder job config over the global settings.
				let processingSettings = AppState.effectiveSettings(for: file, jobs: jobs, global: globalSettings)

				let startTime = Date()
				do {
					let outputs = try ImageProcessor.process(
						file: file,
						settings: processingSettings,
						rename: rename,
						fileIndex: index,
						dryRun: dryRun
					)
					let result = ProcessingResult(
						sourceFile: file,
						outputFiles: outputs,
						error: nil,
						processingTime: Date().timeIntervalSince(startTime)
					)
					DispatchQueue.main.async { [weak self] in
						self?.results.append(result)
						self?.processedCount = index + 1
					}
				} catch {
					let result = ProcessingResult(
						sourceFile: file,
						outputFiles: [],
						error: error.localizedDescription,
						processingTime: Date().timeIntervalSince(startTime)
					)
					DispatchQueue.main.async { [weak self] in
						self?.results.append(result)
						self?.processedCount = index + 1
					}
				}
			}

			DispatchQueue.main.async { [weak self] in
				self?.isProcessing = false
				self?.currentFile = ""
				self?.activeTab = .results
			}
		}
	}

	func addFolder(_ url: URL) {
		guard !folderJobs.contains(where: { $0.url == url }) else { return }
		// New folder inherits the current global defaults as its starting job config.
		folderJobs.append(FolderJob(url: url, config: settings.compression))
		scanFolders()
	}

	func removeFolder(_ url: URL) {
		folderJobs.removeAll { $0.url == url }
		if folderJobs.isEmpty {
			scannedFiles = []
		} else {
			scanFolders()
		}
	}

	/// The effective settings for a file: global settings with the owning folder's
	/// per-folder overrides applied (longest path-prefix match). Falls back to global.
	func effectiveSettings(for file: ImageFile) -> ProcessingSettings {
		Self.effectiveSettings(for: file, jobs: folderJobs, global: settings)
	}

	static func effectiveSettings(for file: ImageFile, jobs: [FolderJob], global: ProcessingSettings) -> ProcessingSettings {
		let filePath = file.url.standardizedFileURL.path
		let match = jobs
			.filter { isUnder(filePath, $0.url.standardizedFileURL.path) }
			.max(by: { $0.url.standardizedFileURL.path.count < $1.url.standardizedFileURL.path.count })
		guard let match else { return global }
		return global.applying(match.config)
	}

	private static func isUnder(_ filePath: String, _ dirPath: String) -> Bool {
		if filePath == dirPath { return true }
		let prefix = dirPath.hasSuffix("/") ? dirPath : dirPath + "/"
		return filePath.hasPrefix(prefix)
	}

	func clearResults() {
		results = []
		processedCount = 0
		totalCount = 0
	}

	/// Rename files without optimization — copies to renamed/ subfolder
	func startRenameOnly() {
		guard !scannedFiles.isEmpty, renameSettings.enabled else { return }

		isProcessing = true
		processedCount = 0
		results = []
		totalCount = scannedFiles.count

		let filesToRename = scannedFiles
		let rename = renameSettings

		DispatchQueue.global(qos: .userInitiated).async {
			for (index, file) in filesToRename.enumerated() {
				DispatchQueue.main.async { [weak self] in
					self?.currentFile = file.filename
				}

				let startTime = Date()
				let renamedDir = file.url.deletingLastPathComponent().appendingPathComponent("renamed")
				try? FileManager.default.createDirectory(at: renamedDir, withIntermediateDirectories: true)

				let newName = rename.apply(to: file.nameWithoutExtension, index: index)
				let ext = file.url.pathExtension
				let destURL = renamedDir.appendingPathComponent("\(newName).\(ext)")

				do {
					if FileManager.default.fileExists(atPath: destURL.path) {
						try FileManager.default.removeItem(at: destURL)
					}
					try FileManager.default.copyItem(at: file.url, to: destURL)

					let output = OutputFile(
						url: destURL,
						format: file.format,
						fileSize: file.originalSize,
						width: file.width ?? 0,
						height: file.height ?? 0,
						originalSize: file.originalSize
					)
					let result = ProcessingResult(
						sourceFile: file,
						outputFiles: [output],
						error: nil,
						processingTime: Date().timeIntervalSince(startTime)
					)
					DispatchQueue.main.async { [weak self] in
						self?.results.append(result)
						self?.processedCount = index + 1
					}
				} catch {
					let result = ProcessingResult(
						sourceFile: file,
						outputFiles: [],
						error: error.localizedDescription,
						processingTime: Date().timeIntervalSince(startTime)
					)
					DispatchQueue.main.async { [weak self] in
						self?.results.append(result)
						self?.processedCount = index + 1
					}
				}
			}

			DispatchQueue.main.async { [weak self] in
				self?.isProcessing = false
				self?.currentFile = ""
				self?.activeTab = .results
			}
		}
	}

	// MARK: - Dock Drop / Open With

	func handleDroppedURLs(_ urls: [URL]) {
		var imageFiles: [URL] = []
		var folderURLs: [URL] = []

		for url in urls {
			var isDir: ObjCBool = false
			FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)

			if isDir.boolValue {
				folderURLs.append(url)
			} else if ImageFormat.from(extension: url.pathExtension.lowercased()) != nil {
				imageFiles.append(url)
			}
		}

		let parentFolders = Set(imageFiles.map { $0.deletingLastPathComponent() })
		let allFolders = folderURLs + Array(parentFolders)
		guard !allFolders.isEmpty else { return }

		let processingSettings = settings
		let outputOverride = dropOutputFolder

		DispatchQueue.global(qos: .userInitiated).async {
			var files = FileScanner.scan(
				directories: allFolders,
				recursive: false,
				includePatterns: ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.avif"],
				excludePatterns: []
			)

			// If specific files were dropped (not folders), filter to only those
			if !imageFiles.isEmpty && folderURLs.isEmpty {
				let droppedPaths = Set(imageFiles.map { $0.path })
				files = files.filter { droppedPaths.contains($0.url.path) }
			}

			guard !files.isEmpty else { return }

			DispatchQueue.main.async { [weak self] in
				guard let self else { return }
				self.scannedFiles = files
				self.totalCount = files.count
				self.processedCount = 0
				self.results = []
				self.isProcessing = true
				self.activeTab = .results
			}

			for (index, file) in files.enumerated() {
				DispatchQueue.main.async { [weak self] in
					self?.currentFile = file.filename
				}

				let startTime = Date()
				do {
					let outputs = try ImageProcessor.process(
						file: file,
						settings: processingSettings,
						rename: RenameSettings(),
						fileIndex: index,
						dryRun: false,
						outputDirectoryOverride: outputOverride
					)
					let result = ProcessingResult(
						sourceFile: file,
						outputFiles: outputs,
						error: nil,
						processingTime: Date().timeIntervalSince(startTime)
					)
					DispatchQueue.main.async { [weak self] in
						self?.results.append(result)
						self?.processedCount = index + 1
					}
				} catch {
					let result = ProcessingResult(
						sourceFile: file,
						outputFiles: [],
						error: error.localizedDescription,
						processingTime: Date().timeIntervalSince(startTime)
					)
					DispatchQueue.main.async { [weak self] in
						self?.results.append(result)
						self?.processedCount = index + 1
					}
				}
			}

			DispatchQueue.main.async { [weak self] in
				self?.isProcessing = false
				self?.currentFile = ""
			}
		}
	}

	// MARK: - Watch Folder Actions

	func addWatchedFolder(_ url: URL) {
		guard !watchedFolders.contains(where: { $0.url == url }) else { return }
		let folder = WatchedFolder(url: url)
		watchedFolders.append(folder)
		saveWatchedFolders()
		startWatching(folder)
	}

	func removeWatchedFolder(_ folder: WatchedFolder) {
		stopWatching(folder)
		watchedFolders.removeAll { $0.id == folder.id }
		saveWatchedFolders()
	}

	func toggleWatchedFolder(_ folder: WatchedFolder) {
		guard let index = watchedFolders.firstIndex(where: { $0.id == folder.id }) else { return }
		watchedFolders[index].isEnabled.toggle()
		saveWatchedFolders()

		if watchedFolders[index].isEnabled {
			startWatching(watchedFolders[index])
		} else {
			stopWatching(folder)
		}
	}

	private func startWatching(_ folder: WatchedFolder) {
		let token = folderWatcher.watch(url: folder.url) { [weak self] in
			self?.handleWatchedFolderChange(folder)
		}
		watcherTokens[folder.id] = token
	}

	private func stopWatching(_ folder: WatchedFolder) {
		guard let token = watcherTokens.removeValue(forKey: folder.id) else { return }
		folderWatcher.unwatch(id: token)
	}

	private func handleWatchedFolderChange(_ folder: WatchedFolder) {
		guard watchAutoOptimize else { return }

		let processingSettings = settings

		DispatchQueue.global(qos: .userInitiated).async { [weak self] in
			guard let self else { return }

			let files = FileScanner.scan(
				directories: [folder.url],
				recursive: false,
				includePatterns: ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.avif"],
				excludePatterns: []
			)

			let newFiles = files.filter { !self.processedFilePaths.contains($0.url.path) }
			guard !newFiles.isEmpty else { return }

			for (index, file) in newFiles.enumerated() {
				let startTime = Date()
				do {
					let outputs = try ImageProcessor.process(
						file: file,
						settings: processingSettings,
						rename: RenameSettings(),
						fileIndex: index,
						dryRun: false
					)
					let result = ProcessingResult(
						sourceFile: file,
						outputFiles: outputs,
						error: nil,
						processingTime: Date().timeIntervalSince(startTime)
					)

					DispatchQueue.main.async { [weak self] in
						self?.processedFilePaths.insert(file.url.path)
						self?.results.append(result)
						self?.watchActivity.insert(
							WatchActivityEntry(
								filename: file.filename,
								folder: folder.url.lastPathComponent,
								timestamp: Date(),
								success: true,
								savedPercent: outputs.first?.savingsPercent
							),
							at: 0
						)
						if (self?.watchActivity.count ?? 0) > 50 {
							self?.watchActivity = Array(self?.watchActivity.prefix(50) ?? [])
						}
					}
				} catch {
					DispatchQueue.main.async { [weak self] in
						self?.processedFilePaths.insert(file.url.path)
						self?.watchActivity.insert(
							WatchActivityEntry(
								filename: file.filename,
								folder: folder.url.lastPathComponent,
								timestamp: Date(),
								success: false,
								savedPercent: nil
							),
							at: 0
						)
					}
				}
			}
		}
	}
}

/// Activity log entry for watched folder processing
struct WatchActivityEntry: Identifiable {
	let id = UUID()
	let filename: String
	let folder: String
	let timestamp: Date
	let success: Bool
	let savedPercent: Double?
}

enum SidebarTab: String, CaseIterable, Identifiable {
	case watch = "Watch"
	case folders = "Folders"
	case settings = "Settings"
	case results = "Results"

	var id: String { rawValue }

	var icon: String {
		switch self {
		case .watch: return "eye"
		case .folders: return "folder"
		case .settings: return "slider.horizontal.3"
		case .results: return "chart.bar"
		}
	}
}
