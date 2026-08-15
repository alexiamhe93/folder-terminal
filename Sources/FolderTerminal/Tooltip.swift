import SwiftUI

/// Applies a hover tooltip, unless the user has turned tooltips off in
/// Settings.
///
/// Every control in the app uses `.tip(_:)` rather than SwiftUI's `.help(_:)`
/// directly, so the preference governs all of them from one place.
private struct TooltipModifier: ViewModifier {
    @AppStorage(AppSettings.showTooltipsKey) private var showTooltips = AppSettings.showTooltipsDefault
    let text: String

    @ViewBuilder
    func body(content: Content) -> some View {
        if showTooltips {
            content.help(text)
        } else {
            content
        }
    }
}

extension View {
    /// Describes this control on hover. Prefer a short phrase naming the
    /// action and, where there is one, its keyboard shortcut.
    func tip(_ text: String) -> some View {
        modifier(TooltipModifier(text: text))
    }
}
