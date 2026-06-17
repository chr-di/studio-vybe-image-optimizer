// swift-tools-version: 5.9
import PackageDescription

let package = Package(
	name: "ImageOptimizer",
	platforms: [.macOS(.v14)],
	targets: [
		.executableTarget(
			name: "ImageOptimizer",
			path: "Sources/ImageOptimizer"
		),
	]
)
