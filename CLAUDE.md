# Image Optimizer — Native macOS App

## Project Overview

A native macOS desktop app for batch image optimization, inspired by ImageOptim. Built with **SwiftUI** + **Swift Package Manager**, no Xcode project required.

**Stack:** Swift 6.2, macOS 14+, SwiftUI, ImageIO, Core Image
**Build:** `swift build` → `bash build.sh` (`--icon` to regen the app icon) → `open ImageOptimizer.app`
**Architecture:** MVVM — Models / Services / Views with single `AppState` ObservableObject
**Design:** Studio Vybe design system — fixed light/cream theme (cream `#FAF8F5`, warm-dark text
`#2D2A26`, gold accent `#D4A574`), **Inter** font bundled + registered at launch (`FontLoader`),
forced light appearance. App icon = Studio Vybe monogram on a warm-dark squircle (`scripts/make-appicon.swift`).

## Compression Modes

Set in Settings → Compression (`ProcessingSettings.compressionMode`):

- **Quality** — encode at one mapped quality (`effectiveQuality(for:)`), original behaviour.
- **Target size** — per-format byte budget (`TargetSizes`: JPEG/PNG/WebP/AVIF KB). For each output,
  `ImageProcessor.encodeToTargetSize` binary-searches the format's quality ladder (`paramLevels`)
  for the highest quality that fits the budget; PNG uses a `pngquant` colour-count ladder (lossless
  as the top rung). If nothing fits at the bottom of the ladder and `allowDownscaleToTarget` is on,
  it progressively shrinks dimensions (`resizeExact`) and retries until it fits — flagged
  "downscaled" in Results. If downscaling is off and nothing fits, the smallest result is kept and
  flagged "target not met" (`OutputFile.targetMet == false`). In target mode the PNG→3-output rule
  drops the lossless-WebP variant (a lossless encode can't target a size).

## Per-folder jobs (Folders tab)

Each folder added in the **Folders** tab is a `FolderJob` carrying its own `FolderCompression`
(mode + per-format targets + downscale + quality + output formats + resize) — see
`Models/FolderJob.swift`. **Output formats** are a set: tick any of JPEG/PNG/WebP/AVIF to emit that
format for every image (true conversion, each at its own quality/target), plus a `keepSourceFormat`
toggle to also optimize each image in its own source format. `determineOutputFormats` =
(source format if kept) ∪ ticked formats, de-duplicated; never empty. Distinct extensions →
distinct filenames (no more `.lossless`/`.qNN` WebP variants — they're explicit ticks now). A new folder inherits the global defaults (`ProcessingSettings.compression`)
and is then editable inline via the reusable `Views/CompressionConfigEditor` (expand the folder row).
At optimize time, `AppState.effectiveSettings(for:)` matches each file to its owning folder by
longest path prefix and applies `settings.applying(job.config)`. Everything else stays **global** on
`ProcessingSettings`: encoder tuning (JPEG/PNG/WebP/AVIF), file patterns, recursive/skip, and rename.
The **Settings** tab edits those globals plus the "Default Job Settings" (the template for new
folders). **Watch mode and dock-drop** still use the global settings, not per-folder.

## Project Structure

```
Package.swift                          # Swift Package Manager manifest
build.sh                              # Build + .app bundle + ad-hoc codesign
Resources/
  Info.plist                           # macOS app metadata + CFBundleDocumentTypes + ATSApplicationFontsPath
  AppIcon.icns                         # App icon (Studio Vybe monogram on warm-dark squircle)
  Fonts/                               # Bundled Inter static OTFs (Regular/Medium/SemiBold/Bold)
  icon/                                # Studio Vybe brand SVGs (app-icon source)
scripts/
  make-appicon.swift                   # Renders a brand SVG → AppIcon.iconset (run via build.sh --icon)
Sources/ImageOptimizer/
  ImageOptimizerApp.swift              # @main App entry + NSApplicationDelegateAdaptor for dock drop
  Theme.swift                          # Studio Vybe palette (light/cream) + Inter font helpers + dimensions
  Models/
    ImageFormat.swift                  # Format enum (JPEG/PNG/WebP/AVIF), OutputFormatMode
    ProcessingSettings.swift           # Quality (default 60), ResizeMode, per-format encoder settings
    ImageFile.swift                    # Input file model (ImageFile), output models (OutputFile, ProcessingResult)
    RenameSettings.swift              # Bulk rename configuration (4 modes)
    AppState.swift                    # Central ObservableObject: folders, processing, watch, dock drop
  Services/
    FileScanner.swift                 # Directory scanning with glob filtering
    ImageProcessor.swift              # Encoding pipeline + target-size binary search (MozJPEG/jpegtran + pngquant/oxipng + cwebp + avifenc)
    FolderWatcher.swift               # DispatchSource-based directory monitor for watch mode
    FontLoader.swift                  # Registers bundled Inter faces at launch (CTFontManager)
  Views/
    ContentView.swift                 # NavigationSplitView shell (sidebar + detail)
    FolderPickerView.swift            # Folder selection + file table + resize + rename + action bar
    SettingsView.swift                # Quality, format, per-format controls, encoder status
    SummaryTableView.swift            # Results table with stats header
    WatchView.swift                   # Auto-watch folder management + activity log
```

## Build & Run

```bash
swift build                    # Compile
swift build 2>&1 | head -50   # Check for errors
bash build.sh                  # Create .app bundle (includes codesign)
open ImageOptimizer.app        # Launch
```

**Important:** Always kill the running app before relaunching after a rebuild:
```bash
pkill -f ImageOptimizer; sleep 0.3; bash build.sh && open ImageOptimizer.app
```

## Conventions

- **Indentation:** Tabs (Swift default)
- **Naming:** Swift conventions — camelCase properties, PascalCase types
- **State management:** Single `AppState` ObservableObject, injected via `.environmentObject()`
- **Image encoding:** Prefer best CLI tool available, fall back to macOS native ImageIO
- **File output:** Always write to `optimized/` subfolder inside each input folder. Never modify originals.
- **Rename output:** Copies to `renamed/` subfolder when using "Rename Only"
- **Error handling:** Processing errors per-file, stored in `ProcessingResult.error`. Don't crash the batch.
- **Never make files larger:** If output is same format as input and >= original size (with no resize), copy original instead.
- **Collapsible sections:** Toggle ON auto-expands settings, toggle OFF collapses. No separate chevron needed.
- **SwiftUI Table + sections:** Use `.layoutPriority(-1)` on Table and `.fixedSize(horizontal: false, vertical: true)` on collapsible sections to prevent Table from starving them of space.

## Processing Rules

These rules are **spec** and must be followed exactly:

| Input | Output(s) |
|-------|-----------|
| JPEG | `optimized/<name>.jpg` — progressive re-encode via best available encoder |
| PNG | `optimized/<name>.png` — optimized PNG (pngquant → oxipng chain) |
| | `optimized/<name>.lossless.webp` — lossless WebP |
| | `optimized/<name>.q80.webp` — lossy WebP (quality number in suffix matches slider) |
| WebP | `optimized/<name>.webp` — re-encoded at chosen quality |
| AVIF | `optimized/<name>.avif` — re-encoded at chosen quality |

When output format override is set (Convert all to WebP/AVIF/JPEG), produce single output in that format instead.

## Encoding Pipeline

### JPEG Encoding (priority order)

For **JPEG→JPEG with no resize**, the app tries both approaches and keeps the smaller result:
1. **jpegtran** (MozJPEG) — lossless optimization directly on JPEG bitstream: progressive encoding, Huffman optimization, metadata stripping. Zero quality loss, typically 2-15% savings.
2. **cjpeg** (MozJPEG or Jpegli) — lossy re-encode via temp PNG. Potentially more savings but with generation loss.
3. Whichever is smaller wins. "Never larger" safeguard still applies vs original.

For **JPEG with resize** or **non-JPEG→JPEG** conversion:
1. **Jpegli** (Google, from libjxl) — ~35% better than libjpeg. Not in Homebrew by default.
2. **MozJPEG cjpeg** — 10-15% smaller than libjpeg. Keg-only: `/opt/homebrew/opt/mozjpeg/bin/cjpeg`
3. **ImageIO** (native) — fallback, libjpeg-based

**Important:** `cjpeg` does NOT accept JPEG or TIFF input. It needs PNG/BMP. Always write a temp PNG for cjpeg input.

### PNG Encoding (configurable engine)

1. Write initial PNG via ImageIO
2. Post-process with selected engine:
   - **pngquant + oxipng** (default) — lossy color quantization → lossless DEFLATE recompression
   - **oxipng** — lossless DEFLATE optimization only
   - **zopflipng** — maximum lossless compression via Zopfli (slow)

### WebP Encoding
- Native ImageIO (macOS 14+) or fallback to `cwebp` CLI

### AVIF Encoding
- Native ImageIO (macOS 14+) or fallback to `avifenc` CLI

## Quality Mapping

The UI slider is 1-100 (default: 60). Map internally per format:
- **JPEG:** 70–92
- **WebP:** 65–85
- **AVIF:** CQ 40–28 (inverted: lower CQ = better)
- **PNG:** Lossless, quality slider doesn't apply

## CLI Tool Dependencies

Install via Homebrew: `brew install mozjpeg pngquant oxipng zopfli webp libavif`

The app works without these — it falls back to macOS native ImageIO. But CLI tools produce significantly smaller files.

**Tool locations (keg-only paths):**
- MozJPEG cjpeg: `/opt/homebrew/opt/mozjpeg/bin/cjpeg`
- MozJPEG jpegtran: `/opt/homebrew/opt/mozjpeg/bin/jpegtran`
- pngquant: `/opt/homebrew/bin/pngquant`
- oxipng: `/opt/homebrew/bin/oxipng`
- zopflipng: `/opt/homebrew/opt/zopfli/bin/zopflipng`
- cwebp: `/opt/homebrew/bin/cwebp`
- avifenc: `/opt/homebrew/bin/avifenc`
- Jpegli (cjpegli): Not available via Homebrew — needs libjxl source build

## Features

### Sidebar Tabs
1. **Watch** — auto-monitored folders (DispatchSource-based file watcher)
2. **Folders** — manual folder selection, scan, resize, rename, optimize
3. **Settings** — quality, format, per-format encoder settings, file patterns
4. **Results** — processing results table with savings stats

### Watch Mode (Auto-Optimize)
- Add folders to watch list → DispatchSource monitors for new files
- 1-second debounce on file system changes
- Auto-processes new images with default settings → writes to `optimized/`
- Persisted via UserDefaults + security-scoped bookmarks (survives app restart without re-prompting)
- Activity log shows recent auto-processed files

### Dock Icon Drop-to-Optimize
- Drag images/folders onto dock icon → instant optimization with default settings
- Registered via `CFBundleDocumentTypes` in Info.plist (JPEG, PNG, WebP, AVIF, folders)
- Handled via `NSApplicationDelegateAdaptor` → `application(_:open:)`
- Auto-switches to Results tab on completion

### Manual Folders (FolderPickerView)
- Pick folders → scan for images (recursive toggle)
- File table showing name, path, size, dimensions with format badges
- **Resize section** (auto-expands on toggle): 3 modes (Longest side / Width / Height) + max dimension + preset buttons (1024/1920/2048/4096)
  - Proportional scaling, no cropping
- **Rename section** (auto-expands on toggle): 4 modes with inline preview
  - Prefix/Suffix, Find & Replace, Regex Replace, Sequential Numbering
  - "Rename Only" button copies to `renamed/` subfolder without optimization
- Action bar: Dry run toggle, Preview (10 files) toggle, Optimize button
- Auto-switches to Results tab on processing completion

### Settings (SettingsView)
- Quality slider (1-100, default 60) with presets (High/Balanced/Small)
- Output format: Same as input / Convert all to WebP/AVIF/JPEG
- Per-format settings: JPEG progressive + strip metadata, PNG engine, WebP effort, AVIF quality + effort
- Encoder status indicators (green checkmark for MozJPEG/Jpegli)
- Include/exclude file patterns

### App Icon
- Studio Vybe monogram (cream) on a warm-dark `#352f36` squircle
- Generated by `scripts/make-appicon.swift` (NSImage renders the brand SVG → iconset → `iconutil`)
- Source SVGs in `Resources/icon/`; regenerate with `bash build.sh --icon`
- Stored as `Resources/AppIcon.icns`, referenced as `CFBundleIconFile: AppIcon` in Info.plist
- Copied to `Contents/Resources/` by build.sh

## Key Architecture Details

### AppState (central state)
- `selectedFolders: [URL]` — manual folder selection
- `scannedFiles: [ImageFile]` — scan results
- `settings: ProcessingSettings` — encoding configuration (quality default 60)
- `renameSettings: RenameSettings` — rename configuration
- `watchedFolders: [WatchedFolder]` — persisted watch list with security-scoped bookmarks
- `watchAutoOptimize: Bool` — master toggle for auto-processing
- `watchActivity: [WatchActivityEntry]` — recent activity log (max 50)
- `activeTab: SidebarTab` — current sidebar selection
- Processing: `isProcessing`, `isDryRun`, `isPreviewMode`, `progress`, `results`
- Methods: `scanFolders()`, `startProcessing()`, `startRenameOnly()`, `handleDroppedURLs(_:)`, `addWatchedFolder(_:)`, `removeWatchedFolder(_:)`, `toggleWatchedFolder(_:)`

### WatchedFolder (persistent model)
- Stores `bookmarkData: Data?` for security-scoped bookmark persistence
- `resolveBookmark()` restores file access on app launch without re-prompting
- Bookmarks auto-refresh when stale

### ImageProcessor (static methods)
- `process(file:settings:rename:fileIndex:dryRun:)` → `[OutputFile]`
- Encoder chain: `encodeJPEG` / `encodePNG` / `encodeWebP` / `encodeAVIF`
- JPEG path: `optimizeJPEGViaJpegtran` → `encodeJPEGViaJpegli` → `encodeJPEGViaMozJPEG` → ImageIO
- CLI tool execution via `runCLITool(_:arguments:required:)` with multi-path search
- Resize via `resizeIfNeeded(_:maxDimension:mode:)` using CGContext — supports longest side, width-only, height-only
- "Never larger" safeguard: copies original if output >= original for same format

### FolderWatcher (DispatchSource)
- `watch(url:onChange:)` → UUID token
- `unwatch(id:)` / `unwatchAll()`
- Uses `O_EVTONLY` file descriptor + `.write` event mask
- 1-second debounce timer per watcher

### Build Pipeline
- `build.sh`: swift build → create .app bundle → copy binary + Info.plist + AppIcon.icns → ad-hoc codesign
- Ad-hoc signing enables security-scoped bookmarks and helps TCC remember permissions

## Current Status

**Phase: Functional — compiles and runs, core features working**

- Compilation: clean build, zero errors/warnings
- App icon: Studio Vybe monogram on a warm-dark squircle (dock + Finder)
- JPEG optimization: working via MozJPEG (cjpeg for lossy, jpegtran for lossless)
- PNG optimization: working via pngquant → oxipng chain
- WebP/AVIF: working via native ImageIO + CLI fallbacks
- Rename: working (all 4 modes) via inline UI in Folders view, auto-expands on toggle
- Resize: working with 3 modes (longest side/width/height), auto-expands on toggle
- Watch mode: implemented (DispatchSource-based) with bookmark persistence
- Dock drop: implemented (NSApplicationDelegateAdaptor)
- Results auto-switch: working (activeTab → .results on completion)
- "Never larger" safeguard: working
- Security-scoped bookmarks: persist folder access across app restarts

## What NOT to Build (yet)

- No srcset generation
- No cloud/server component — fully local desktop app

---

# Roadmap & Notes

## Next Steps

### Testing & Polish
1. **End-to-end testing** — Run full optimization on mixed image folder, verify all output rules
2. **Watch mode testing** — Add watched folder, copy image into it, verify auto-optimization within ~2s
3. **Dock drop testing** — Drag images onto dock icon, verify instant processing
4. **Rename testing** — All 4 modes, collision handling, preview accuracy
5. **Resize testing** — All 3 modes (longest side/width/height) with different dimension values
6. **Edge cases** — Empty folders, permission denied, very large images, missing CLI tools gracefully handled
7. **UI polish** — Dark/light mode consistency, layout at different window sizes

### Potential Improvements
- Collision handling for rename (auto-append -1, -2 when filename exists)
- Drag-and-drop folders onto the Folders view (not just dock icon)
- Cancellation support for long batch processing
- Per-file selection/deselection in the file table
- Export/share results summary
- Settings persistence via UserDefaults (quality, format, patterns survive restart)

## Known Issues / Gotchas

- **Stale binary on relaunch:** `open ImageOptimizer.app` may reuse the running process instead of launching the new build. Always `pkill -f ImageOptimizer` first.
- **SwiftUI Table greedy layout:** Table consumes all vertical space. Collapsible sections below it need `.fixedSize(horizontal: false, vertical: true)` and Table needs `.layoutPriority(-1)`.
- **cjpeg TIFF bug:** MozJPEG's cjpeg does NOT accept TIFF input (only JPEG, PNG, BMP). Always use temp PNG as intermediate format.
- **TCC permission prompts:** macOS re-prompts for folder access when app binary changes (new code signature). Ad-hoc signing + security-scoped bookmarks mitigate this.
- **Toggle inside Button:** On macOS SwiftUI, nesting a Toggle inside a Button can cause the Toggle to render with zero height. Use a plain HStack instead.

