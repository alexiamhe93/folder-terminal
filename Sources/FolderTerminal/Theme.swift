import AppKit
import SwiftTerm
import SwiftUI

/// The app's small family of dark themes. Every surface — window chrome, panel
/// headers, file browser, terminal — draws semantic colours from here so a
/// theme changes the whole instrument rather than tinting isolated controls.
///
/// `Metrics`, `Typography` and `Motion` do the same job for geometry, type and
/// animation: views name a token instead of a number, so a row in the column
/// browser and a row in the tree cannot drift apart.
enum Theme {
    // MARK: Semantic colours

    static var accentNSColor: NSColor { palette.accent }
    static var accent: SwiftUI.Color { SwiftUI.Color(nsColor: accentNSColor) }
    static var accentBrightNSColor: NSColor { palette.accentBright }
    static var accentBright: SwiftUI.Color { SwiftUI.Color(nsColor: accentBrightNSColor) }

    static var terminalBackgroundNSColor: NSColor { palette.terminalBackground }
    static var panelBackgroundNSColor: NSColor { palette.panelBackground }
    static var headerBackgroundNSColor: NSColor { palette.headerBackground }
    static var dividerNSColor: NSColor { palette.divider }

    static var terminalBackground: SwiftUI.Color { SwiftUI.Color(nsColor: terminalBackgroundNSColor) }
    static var panelBackground: SwiftUI.Color { SwiftUI.Color(nsColor: panelBackgroundNSColor) }
    static var headerBackground: SwiftUI.Color { SwiftUI.Color(nsColor: headerBackgroundNSColor) }
    static var divider: SwiftUI.Color { SwiftUI.Color(nsColor: dividerNSColor) }

    static var terminalForegroundNSColor: NSColor { palette.primaryText }
    static var terminalCaretNSColor: NSColor { accentBrightNSColor }
    static var primaryText: SwiftUI.Color { SwiftUI.Color(nsColor: palette.primaryText) }
    static var secondaryText: SwiftUI.Color { SwiftUI.Color(nsColor: palette.secondaryText) }
    static let unavailable = SwiftUI.Color(nsColor: .systemOrange)

    // MARK: Selection

    /// Selection in the panel that currently has focus.
    static var selectionHighlight: SwiftUI.Color { accent.opacity(0.34) }
    /// Edge of a focused selection — the fill alone still reads soft at this
    /// row height, so the stroke carries the definition.
    static var selectionBorder: SwiftUI.Color { accentBright.opacity(0.85) }
    /// Selection in a panel that has lost focus — Finder makes the same
    /// distinction so you can tell which list your keys will act on.
    static var inactiveSelectionHighlight: SwiftUI.Color { SwiftUI.Color(nsColor: palette.inactiveSelection) }
    static var hoverHighlight: SwiftUI.Color { SwiftUI.Color.white.opacity(0.06) }
    static var headerSelectedBackground: SwiftUI.Color { accent.opacity(0.18) }
    static var focusBorder: SwiftUI.Color { accentBright }
    static var pathHighlight: SwiftUI.Color { accent.opacity(0.13) }
    static var pathHighlightBorder: SwiftUI.Color { accent.opacity(0.42) }

    // MARK: Metrics

    /// Geometry tokens. Panel headers, browser rows and column widths all size
    /// themselves from here rather than from literals scattered across views.
    enum Metrics {
        /// Panel headers, the browser navigation bar, the terminal status bar.
        static let headerHeight: CGFloat = 32
        /// One file row, in every view mode.
        static let rowHeight: CGFloat = 26
        /// File and folder icons in browser rows.
        static let iconSize: CGFloat = 16
        /// Outer horizontal padding inside a header or row.
        static let gutter: CGFloat = 12
        /// Standard gap between adjacent controls.
        static let gap: CGFloat = 8
        /// Gap between tightly related elements (icon and its label).
        static let tight: CGFloat = 4
        /// Width of one Miller column.
        static let columnWidth: CGFloat = 220
        /// Indent added per level of tree nesting.
        static let treeIndent: CGFloat = 14
        /// Border drawn around the selected panel.
        static let focusRing: CGFloat = 2
        /// Draggable split dividers.
        static let dividerThickness: CGFloat = 6
        /// Corner radius on selection fills and small chips.
        static let cornerRadius: CGFloat = 4
    }

    // MARK: Typography

    /// The type scale. Four sizes, one family (SF), used everywhere.
    enum Typography {
        /// Small uppercase section labels.
        static let sectionLabel = Font.system(size: 11, weight: .semibold)
        /// The default: file rows, menu-adjacent labels.
        static let row = Font.system(size: 12, weight: .regular)
        /// A row that needs to stand out (a folder on the current path).
        static let rowEmphasis = Font.system(size: 12, weight: .medium)
        /// Header and status-bar text.
        static let status = Font.system(size: 11, weight: .regular)
        /// Paths and other text where character alignment matters.
        static let path = Font.system(size: 11, weight: .regular, design: .monospaced)
    }

    // MARK: Motion

    /// Short, uniform animation. Long enough to read as movement, short enough
    /// that the interface never feels like it is catching up.
    enum Motion {
        static let selection = Animation.easeOut(duration: 0.15)
        static let disclosure = Animation.easeOut(duration: 0.2)
    }

    // MARK: Palettes

    static var ansiColors: [SwiftTerm.Color] { palette.ansiColors }

    static func previewColors(for theme: AppTheme) -> [SwiftUI.Color] {
        let preview = palette(for: theme)
        return [preview.terminalBackground, preview.headerBackground, preview.accent, preview.accentBright]
            .map { SwiftUI.Color(nsColor: $0) }
    }

    private struct Palette {
        let accent: NSColor
        let accentBright: NSColor
        let terminalBackground: NSColor
        let panelBackground: NSColor
        let headerBackground: NSColor
        let divider: NSColor
        let primaryText: NSColor
        let secondaryText: NSColor
        let inactiveSelection: NSColor
        let ansiColors: [SwiftTerm.Color]
    }

    private static var palette: Palette { palette(for: AppSettings.theme) }

    private static func palette(for theme: AppTheme) -> Palette {
        switch theme {
        case .graphite:
            return Palette(
                accent: rgb(0x2A, 0xA1, 0x98),
                accentBright: rgb(0x3D, 0xD6, 0xCA),
                terminalBackground: grey(0x0A),
                panelBackground: grey(0x14),
                headerBackground: grey(0x1C),
                divider: grey(0x2E),
                primaryText: grey(0xEB),
                secondaryText: grey(0x9E),
                inactiveSelection: grey(0x3A),
                ansiColors: ansiPalette([
                    0x073642, 0xDC322F, 0x859900, 0xB58900,
                    0x268BD2, 0xD33682, 0x2AA198, 0xEEE8D5,
                    0x586E75, 0xF94C49, 0xA8BF1A, 0xDCAE1D,
                    0x4FADEE, 0xE85AA0, 0x3DD6CA, 0xFDF6E3,
                ])
            )
        case .midnight:
            return Palette(
                accent: rgb(0x58, 0xA6, 0xFF),
                accentBright: rgb(0x79, 0xC0, 0xFF),
                terminalBackground: rgb(0x0D, 0x11, 0x17),
                panelBackground: rgb(0x0D, 0x11, 0x17),
                headerBackground: rgb(0x16, 0x1B, 0x22),
                divider: rgb(0x30, 0x36, 0x3D),
                primaryText: rgb(0xF0, 0xF6, 0xFC),
                secondaryText: rgb(0x8B, 0x94, 0x9E),
                inactiveSelection: rgb(0x30, 0x36, 0x3D),
                ansiColors: ansiPalette([
                    0x484F58, 0xFF7B72, 0x3FB950, 0xD29922,
                    0x58A6FF, 0xBC8CFF, 0x39C5CF, 0xB1BAC4,
                    0x6E7681, 0xFFA198, 0x56D364, 0xE3B341,
                    0x79C0FF, 0xD2A8FF, 0x56D4DD, 0xF0F6FC,
                ])
            )
        case .mocha:
            return Palette(
                accent: rgb(0x89, 0xB4, 0xFA),
                accentBright: rgb(0xB4, 0xBE, 0xFE),
                terminalBackground: rgb(0x11, 0x11, 0x1B),
                panelBackground: rgb(0x1E, 0x1E, 0x2E),
                headerBackground: rgb(0x18, 0x18, 0x25),
                divider: rgb(0x45, 0x47, 0x5A),
                primaryText: rgb(0xCD, 0xD6, 0xF4),
                secondaryText: rgb(0xA6, 0xAD, 0xC8),
                inactiveSelection: rgb(0x45, 0x47, 0x5A),
                ansiColors: ansiPalette([
                    0x45475A, 0xF38BA8, 0xA6E3A1, 0xF9E2AF,
                    0x89B4FA, 0xF5C2E7, 0x94E2D5, 0xBAC2DE,
                    0x585B70, 0xF38BA8, 0xA6E3A1, 0xF9E2AF,
                    0x89B4FA, 0xF5C2E7, 0x94E2D5, 0xCDD6F4,
                ])
            )
        }
    }

    private static func grey(_ level: Int) -> NSColor {
        let value = Double(level) / 255.0
        return NSColor(calibratedWhite: value, alpha: 1)
    }

    private static func rgb(_ red: Int, _ green: Int, _ blue: Int) -> NSColor {
        NSColor(
            srgbRed: Double(red) / 255.0,
            green: Double(green) / 255.0,
            blue: Double(blue) / 255.0,
            alpha: 1
        )
    }

    private static func ansi(_ red: Int, _ green: Int, _ blue: Int) -> SwiftTerm.Color {
        SwiftTerm.Color(
            red: UInt16(red) * 257,
            green: UInt16(green) * 257,
            blue: UInt16(blue) * 257
        )
    }

    private static func ansiPalette(_ values: [Int]) -> [SwiftTerm.Color] {
        values.map { value in
            ansi((value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF)
        }
    }
}
