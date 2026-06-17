import SwiftUI

/// Studio Vybe design system — light/cream theme.
/// Palette sourced from studio-vybe-for-you/design-tokens/tokens.css and the brand logo SVGs.
/// The app forces a light appearance (see ImageOptimizerApp) so these fixed hexes stay on-brand
/// regardless of the system Dark Mode setting.
enum Theme {
	// MARK: - Colors (Studio Vybe brand, fixed light/cream)

	static let accent = Color(hex: 0xD4A574)        // Warm gold — primary actions, highlights
	static let accentHover = Color(hex: 0xC2925E)   // Darker gold — pressed/hover
	static let onAccent = Color(hex: 0x2D2A26)      // Warm dark text drawn on gold fills

	static let background = Color(hex: 0xFAF8F5)     // Cream page background
	static let surface = Color(hex: 0xF5F2ED)        // Panel / card / header surface
	static let surfaceSecondary = Color(hex: 0xEDEAE3) // Inset bars / sidebar surface

	static let textPrimary = Color(hex: 0x2D2A26)   // Warm dark text
	static let textSecondary = Color(hex: 0x8A8178) // Warm muted text

	static let border = Color(hex: 0xC8C3BB)        // Subtle border
	static let borderStrong = Color(hex: 0xB0ADA6)  // Strong border

	static let success = Color(hex: 0x22C55E)
	static let warning = Color(hex: 0xF59E0B)
	static let error = Color(hex: 0xB85C38)         // Terracotta — brand error
	static let destructive = Color(hex: 0xB85C38)

	// MARK: - Typography (Inter — bundled, registered at launch by FontLoader)

	static let fontFamily = "Inter"

	/// Inter at an explicit point size + weight, using the bundled static faces.
	static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
		.custom(postScriptName(for: weight), size: size)
	}

	private static func postScriptName(for weight: Font.Weight) -> String {
		switch weight {
		case .bold, .heavy, .black: return "Inter-Bold"
		case .semibold: return "Inter-SemiBold"
		case .medium: return "Inter-Medium"
		default: return "Inter-Regular"
		}
	}

	// Inter equivalents of the semantic text styles used across the views.
	static let caption2 = font(10)
	static let caption = font(11)
	static let callout = font(12)
	static let body = font(13)
	static let headline = font(13, .semibold)
	static let title3 = font(15, .semibold)
	static let title2 = font(18, .semibold)

	// MARK: - Dimensions

	static let cornerRadius: CGFloat = 8           // Brand uses restrained radii
	static let cornerRadiusSmall: CGFloat = 6
	static let sidebarWidth: CGFloat = 280
	static let spacing: CGFloat = 12
	static let spacingSmall: CGFloat = 8
	static let spacingLarge: CGFloat = 20
}

extension Color {
	init(hex: UInt, opacity: Double = 1.0) {
		self.init(
			.sRGB,
			red: Double((hex >> 16) & 0xFF) / 255,
			green: Double((hex >> 8) & 0xFF) / 255,
			blue: Double(hex & 0xFF) / 255,
			opacity: opacity
		)
	}
}
