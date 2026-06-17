import Foundation

/// Monitors directories for file system changes using DispatchSource.
/// Fires a debounced callback when files are added, removed, or modified.
final class FolderWatcher {

	struct WatchEntry {
		let url: URL
		let fileDescriptor: Int32
		let source: DispatchSourceFileSystemObject
		var debounceTimer: DispatchSourceTimer?
	}

	private var entries: [UUID: WatchEntry] = [:]
	private let queue = DispatchQueue(label: "com.diansolutions.FolderWatcher", qos: .utility)
	private let debounceInterval: TimeInterval = 1.0

	/// Start watching a folder for changes.
	/// Returns a token UUID to stop watching later.
	func watch(url: URL, onChange: @escaping () -> Void) -> UUID {
		let id = UUID()
		let fd = open(url.path, O_EVTONLY)
		guard fd >= 0 else { return id }

		let source = DispatchSource.makeFileSystemObjectSource(
			fileDescriptor: fd,
			eventMask: .write,
			queue: queue
		)

		let entry = WatchEntry(url: url, fileDescriptor: fd, source: source)

		source.setEventHandler { [weak self] in
			guard let self else { return }
			self.debounce(id: id, callback: onChange)
		}

		source.setCancelHandler {
			close(fd)
		}

		source.resume()
		entries[id] = entry
		return id
	}

	/// Stop watching a specific folder.
	func unwatch(id: UUID) {
		guard let entry = entries.removeValue(forKey: id) else { return }
		entry.debounceTimer?.cancel()
		entry.source.cancel()
	}

	/// Stop watching all folders.
	func unwatchAll() {
		for (id, _) in entries {
			unwatch(id: id)
		}
	}

	private func debounce(id: UUID, callback: @escaping () -> Void) {
		// Cancel any existing debounce timer for this watcher
		entries[id]?.debounceTimer?.cancel()

		let timer = DispatchSource.makeTimerSource(queue: queue)
		timer.schedule(deadline: .now() + debounceInterval)
		timer.setEventHandler {
			DispatchQueue.main.async {
				callback()
			}
		}
		timer.resume()
		entries[id]?.debounceTimer = timer
	}

	deinit {
		unwatchAll()
	}
}
