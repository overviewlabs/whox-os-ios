import SwiftUI
import UIKit

enum WHOXTheme {
    static let background = Color(uiColor: .systemBackground)
    static let surface = Color(uiColor: .secondarySystemBackground)
    static let panel = surface
    static let border = Color(uiColor: .separator).opacity(0.7)
    static let primaryText = Color.primary
    static let secondaryText = Color.secondary
    static let inverseText = Color(uiColor: .systemBackground)
    static let avatarSurface = Color(uiColor: .tertiarySystemFill)
    static let drawerOverlay = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 0.13, alpha: 0.72)
                : UIColor(white: 0.88, alpha: 0.78)
        }
    )
    /// Adaptive monochrome tint: black in Light Mode and white in Dark Mode.
    static let action = Color.primary
    static let accent = action
}
