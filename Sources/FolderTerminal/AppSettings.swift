import FolderTerminalCore
import SwiftUI

/// User preferences, stored in `UserDefaults`.
///
/// Views read these through `@AppStorage` with the keys below rather than
/// through a shared object, so a change repaints only what depends on it.
/// `AppSettings` itself exists to keep the keys and defaults in one place.
enum AppSettings {
    /// The colour system used by the workspace and every embedded terminal.
    /// Themes are intentionally few: each one is a complete, tested set of
    /// semantic colours rather than an accent picker that can create
    /// unreadable combinations.
    static let themeKey = "Theme"
    static let themeDefault = AppTheme.graphite

    /// Whether hovering a control shows its tooltip. See `View.tip(_:)`.
    static let showTooltipsKey = "ShowTooltips"
    static let showTooltipsDefault = true

    /// View mode given to newly created file panels. Existing panels keep
    /// whatever mode they were saved with.
    static let defaultViewModeKey = "DefaultFileViewMode"
    static let defaultViewModeDefault = FileViewMode.column

    /// Whether new file panels start with hidden files visible.
    static let defaultShowHiddenFilesKey = "DefaultShowHiddenFiles"
    static let defaultShowHiddenFilesDefault = false

    /// How a new panel divides the selected one. Note the model's naming: a
    /// `.horizontal` split is a *horizontal divider*, so the panels stack as
    /// rows; `.vertical` puts them side by side as columns.
    static let newPanelPlacementKey = "NewPanelPlacement"
    static let newPanelPlacementDefault = SplitOrientation.horizontal

    static var defaultViewMode: FileViewMode {
        guard let raw = UserDefaults.standard.string(forKey: defaultViewModeKey),
              let mode = FileViewMode(rawValue: raw) else { return defaultViewModeDefault }
        return mode
    }

    static var defaultShowHiddenFiles: Bool {
        guard UserDefaults.standard.object(forKey: defaultShowHiddenFilesKey) != nil else {
            return defaultShowHiddenFilesDefault
        }
        return UserDefaults.standard.bool(forKey: defaultShowHiddenFilesKey)
    }

    static var newPanelPlacement: SplitOrientation {
        guard let raw = UserDefaults.standard.string(forKey: newPanelPlacementKey),
              let orientation = SplitOrientation(rawValue: raw) else { return newPanelPlacementDefault }
        return orientation
    }

    static var theme: AppTheme {
        guard let raw = UserDefaults.standard.string(forKey: themeKey),
              let theme = AppTheme(rawValue: raw) else { return themeDefault }
        return theme
    }

    /// A new file browser panel built from the current preferences. Every
    /// "add a file panel" path goes through here so the settings actually
    /// apply, wherever the panel was created from.
    static func newFilePanel(at folder: String) -> WorkspacePanel {
        .file(at: folder, viewMode: defaultViewMode, showHiddenFiles: defaultShowHiddenFiles)
    }

    /// The same, as a panel *kind*, for replacing an existing panel in place.
    static func newFilePanelKind(at folder: String) -> WorkspacePanelKind {
        .file(FilePanelState(
            rootFolder: folder,
            viewMode: defaultViewMode,
            showHiddenFiles: defaultShowHiddenFiles
        ))
    }

    static var homeFolder: String {
        FileManager.default.homeDirectoryForCurrentUser.path
    }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case graphite
    case midnight
    case mocha

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .graphite: return "Graphite"
        case .midnight: return "Midnight"
        case .mocha: return "Mocha"
        }
    }

    var summary: String {
        switch self {
        case .graphite: return "Neutral near-black with a crisp teal signal."
        case .midnight: return "Cool blue-black with GitHub-inspired clarity."
        case .mocha: return "A softer violet-black based on Catppuccin Mocha."
        }
    }
}

extension SplitOrientation {
    /// Described by the result, not by the divider: what the user picks is
    /// whether panels end up stacked or beside each other.
    var placementName: String {
        switch self {
        case .horizontal: return "Rows (stacked)"
        case .vertical: return "Columns (side by side)"
        }
    }
}

extension FileViewMode {
    var displayName: String {
        switch self {
        case .list: return "List"
        case .column: return "Column"
        case .tree: return "Tree"
        }
    }

    var symbolName: String {
        switch self {
        case .list: return "list.bullet"
        case .column: return "rectangle.split.3x1"
        case .tree: return "list.bullet.indent"
        }
    }
}
