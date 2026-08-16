import Foundation

public enum SplitOrientation: String, Codable, CaseIterable, Sendable {
    case horizontal
    case vertical
}

public enum FileViewMode: String, Codable, CaseIterable, Sendable {
    case list
    /// Finder-style Miller columns: one column per level of the current path.
    case column
    case tree
}

public struct FilePanelState: Codable, Equatable, Sendable {
    public var rootFolder: String
    public var currentFolder: String
    public var backHistory: [String]
    public var forwardHistory: [String]
    public var bookmark: Data?
    public var viewMode: FileViewMode
    public var requiresReselection: Bool
    public var showHiddenFiles: Bool
    public var sortField: FileSortField
    public var sortAscending: Bool

    public init(
        rootFolder: String,
        currentFolder: String? = nil,
        backHistory: [String] = [],
        forwardHistory: [String] = [],
        bookmark: Data? = nil,
        viewMode: FileViewMode = .column,
        requiresReselection: Bool = false,
        showHiddenFiles: Bool = false,
        sortField: FileSortField = .name,
        sortAscending: Bool = true
    ) {
        self.rootFolder = rootFolder
        self.currentFolder = currentFolder ?? rootFolder
        self.backHistory = backHistory
        self.forwardHistory = forwardHistory
        self.bookmark = bookmark
        self.viewMode = viewMode
        self.requiresReselection = requiresReselection
        self.showHiddenFiles = showHiddenFiles
        self.sortField = sortField
        self.sortAscending = sortAscending
    }

    private enum CodingKeys: String, CodingKey {
        case rootFolder
        case currentFolder
        case backHistory
        case forwardHistory
        case bookmark
        case viewMode
        case requiresReselection
        case showHiddenFiles
        case sortField
        case sortAscending
    }

    // Decoded with defaults so workspaces saved before these fields existed
    // load unchanged.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rootFolder = try container.decode(String.self, forKey: .rootFolder)
        currentFolder = try container.decode(String.self, forKey: .currentFolder)
        backHistory = try container.decodeIfPresent([String].self, forKey: .backHistory) ?? []
        forwardHistory = try container.decodeIfPresent([String].self, forKey: .forwardHistory) ?? []
        bookmark = try container.decodeIfPresent(Data.self, forKey: .bookmark)
        // `try?` rather than `try`: a view mode written by a newer build must
        // not fail the whole workspace load. Saved panels keep falling back to
        // `.list` so an existing workspace does not shift mode under the user
        // — only newly created panels get the `.column` default.
        viewMode = (try? container.decodeIfPresent(FileViewMode.self, forKey: .viewMode)) ?? .list
        requiresReselection = try container.decodeIfPresent(Bool.self, forKey: .requiresReselection) ?? false
        showHiddenFiles = try container.decodeIfPresent(Bool.self, forKey: .showHiddenFiles) ?? false
        sortField = try container.decodeIfPresent(FileSortField.self, forKey: .sortField) ?? .name
        sortAscending = try container.decodeIfPresent(Bool.self, forKey: .sortAscending) ?? true
    }
}

extension FilePanelState {
    /// How many steps of back/forward history a panel keeps. Browsing is a
    /// long-lived activity and every step used to be appended and saved
    /// forever, so a panel open for weeks grew an unbounded list of folders in
    /// the workspace file. Oldest entries are dropped once the cap is reached.
    public static let historyLimit = 200

    /// Moves to `path`, recording the departure so Back can return to it.
    /// Navigating to the folder already shown records nothing.
    public mutating func navigate(to path: String, recordHistory: Bool = true) {
        if recordHistory && currentFolder != path {
            backHistory.append(currentFolder)
            if backHistory.count > Self.historyLimit {
                backHistory.removeFirst(backHistory.count - Self.historyLimit)
            }
            forwardHistory = []
        }
        currentFolder = path
    }

    @discardableResult
    public mutating func goBack() -> Bool {
        guard let destination = backHistory.popLast() else { return false }
        forwardHistory.append(currentFolder)
        if forwardHistory.count > Self.historyLimit {
            forwardHistory.removeFirst(forwardHistory.count - Self.historyLimit)
        }
        currentFolder = destination
        return true
    }

    @discardableResult
    public mutating func goForward() -> Bool {
        guard let destination = forwardHistory.popLast() else { return false }
        backHistory.append(currentFolder)
        if backHistory.count > Self.historyLimit {
            backHistory.removeFirst(backHistory.count - Self.historyLimit)
        }
        currentFolder = destination
        return true
    }
}

public struct TerminalPanelState: Codable, Equatable, Sendable {
    public var linkedFilePanelID: UUID?
    public var environmentFolder: String?
    public var lastWorkingFolder: String?

    public init(
        linkedFilePanelID: UUID? = nil,
        environmentFolder: String? = nil,
        lastWorkingFolder: String? = nil
    ) {
        self.linkedFilePanelID = linkedFilePanelID
        self.environmentFolder = environmentFolder
        self.lastWorkingFolder = lastWorkingFolder
    }

    private enum CodingKeys: String, CodingKey {
        case linkedFilePanelID
        case environmentFolder
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        linkedFilePanelID = try container.decodeIfPresent(UUID.self, forKey: .linkedFilePanelID)
        environmentFolder = try container.decodeIfPresent(String.self, forKey: .environmentFolder)
        lastWorkingFolder = nil
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(linkedFilePanelID, forKey: .linkedFilePanelID)
        try container.encodeIfPresent(environmentFolder, forKey: .environmentFolder)
    }
}

public enum WorkspacePanelKind: Codable, Equatable, Sendable {
    case file(FilePanelState)
    case terminal(TerminalPanelState)
}

public struct WorkspacePanel: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var kind: WorkspacePanelKind

    public init(id: UUID = UUID(), kind: WorkspacePanelKind) {
        self.id = id
        self.kind = kind
    }

    public static func file(
        at folder: String,
        viewMode: FileViewMode = .column,
        showHiddenFiles: Bool = false,
        id: UUID = UUID()
    ) -> WorkspacePanel {
        WorkspacePanel(id: id, kind: .file(FilePanelState(
            rootFolder: folder,
            viewMode: viewMode,
            showHiddenFiles: showHiddenFiles
        )))
    }

    public static func terminal(
        linkedTo filePanelID: UUID? = nil,
        environmentFolder: String? = nil,
        id: UUID = UUID()
    ) -> WorkspacePanel {
        WorkspacePanel(
            id: id,
            kind: .terminal(TerminalPanelState(
                linkedFilePanelID: filePanelID,
                environmentFolder: environmentFolder
            ))
        )
    }
}

public struct WorkspaceSplit: Codable, Equatable, Sendable {
    public var id: UUID
    public var orientation: SplitOrientation
    public var ratio: Double
    public var first: WorkspaceLayout
    public var second: WorkspaceLayout

    /// The narrowest a split may be dragged. Both sides stay reachable, so a
    /// divider can always be dragged back.
    public static let ratioRange: ClosedRange<Double> = 0.1...0.9

    public static func clamp(ratio: Double) -> Double {
        guard ratio.isFinite else { return 0.5 }
        return min(max(ratio, ratioRange.lowerBound), ratioRange.upperBound)
    }

    public init(
        id: UUID = UUID(),
        orientation: SplitOrientation,
        ratio: Double = 0.5,
        first: WorkspaceLayout,
        second: WorkspaceLayout
    ) {
        self.id = id
        self.orientation = orientation
        self.ratio = Self.clamp(ratio: ratio)
        self.first = first
        self.second = second
    }

    /// Synthesised decoding would assign `ratio` straight from the file and
    /// skip the clamp in `init`, so a workspace carrying 0, 1, or NaN — an
    /// older build, a truncated write, a hand edit — restored a split with one
    /// side sized to nothing and no divider left on screen to drag back.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            orientation: try container.decode(SplitOrientation.self, forKey: .orientation),
            ratio: try container.decode(Double.self, forKey: .ratio),
            first: try container.decode(WorkspaceLayout.self, forKey: .first),
            second: try container.decode(WorkspaceLayout.self, forKey: .second)
        )
    }
}

public indirect enum WorkspaceLayout: Codable, Equatable, Sendable {
    case panel(WorkspacePanel)
    case split(WorkspaceSplit)

    public var panelIDs: [UUID] {
        switch self {
        case .panel(let panel): return [panel.id]
        case .split(let split): return split.first.panelIDs + split.second.panelIDs
        }
    }

    public var panels: [WorkspacePanel] {
        switch self {
        case .panel(let panel): return [panel]
        case .split(let split): return split.first.panels + split.second.panels
        }
    }

    public func panel(id: UUID) -> WorkspacePanel? {
        switch self {
        case .panel(let panel): return panel.id == id ? panel : nil
        case .split(let split): return split.first.panel(id: id) ?? split.second.panel(id: id)
        }
    }

    @discardableResult
    public mutating func updatePanel(id: UUID, _ transform: (inout WorkspacePanel) -> Void) -> Bool {
        switch self {
        case .panel(var panel) where panel.id == id:
            transform(&panel)
            self = .panel(panel)
            return true
        case .panel:
            return false
        case .split(var split):
            if split.first.updatePanel(id: id, transform) || split.second.updatePanel(id: id, transform) {
                self = .split(split)
                return true
            }
            return false
        }
    }

    @discardableResult
    public mutating func splitPanel(
        id: UUID,
        orientation: SplitOrientation,
        newPanel: WorkspacePanel,
        placeAfter: Bool = true
    ) -> Bool {
        switch self {
        case .panel(let panel) where panel.id == id:
            let old = WorkspaceLayout.panel(panel)
            let new = WorkspaceLayout.panel(newPanel)
            self = .split(WorkspaceSplit(
                orientation: orientation,
                first: placeAfter ? old : new,
                second: placeAfter ? new : old
            ))
            return true
        case .panel:
            return false
        case .split(var split):
            if split.first.splitPanel(id: id, orientation: orientation, newPanel: newPanel, placeAfter: placeAfter)
                || split.second.splitPanel(id: id, orientation: orientation, newPanel: newPanel, placeAfter: placeAfter) {
                self = .split(split)
                return true
            }
            return false
        }
    }

    @discardableResult
    public mutating func removePanel(id: UUID) -> WorkspacePanel? {
        switch self {
        case .panel:
            return nil
        case .split(var split):
            if case .panel(let panel) = split.first, panel.id == id {
                self = split.second
                return panel
            }
            if case .panel(let panel) = split.second, panel.id == id {
                self = split.first
                return panel
            }
            if let removed = split.first.removePanel(id: id) {
                self = .split(split)
                return removed
            }
            if let removed = split.second.removePanel(id: id) {
                self = .split(split)
                return removed
            }
            return nil
        }
    }

    @discardableResult
    public mutating func updateRatio(splitID: UUID, ratio: Double) -> Bool {
        switch self {
        case .panel:
            return false
        case .split(var split):
            if split.id == splitID {
                split.ratio = WorkspaceSplit.clamp(ratio: ratio)
                self = .split(split)
                return true
            }
            if split.first.updateRatio(splitID: splitID, ratio: ratio)
                || split.second.updateRatio(splitID: splitID, ratio: ratio) {
                self = .split(split)
                return true
            }
            return false
        }
    }

    @discardableResult
    public mutating func movePanel(
        id: UUID,
        beside targetID: UUID,
        orientation: SplitOrientation,
        placeAfter: Bool = true
    ) -> Bool {
        guard id != targetID, panel(id: id) != nil, panel(id: targetID) != nil else { return false }
        // The move is a removal followed by a re-insert, and the removal has
        // already mutated the tree by the time the insert runs. If the insert
        // ever fails the panel would be gone from a layout that reports the
        // move as failed, so restore the tree as it was rather than drop it.
        let original = self
        guard let moved = removePanel(id: id) else { return false }
        if splitPanel(id: targetID, orientation: orientation, newPanel: moved, placeAfter: placeAfter) {
            return true
        }
        self = original
        return false
    }
}

public struct WorkspaceDocument: Codable, Equatable, Sendable {
    public var version: Int
    public var layout: WorkspaceLayout
    public var selectedPanelID: UUID?

    public init(version: Int = 1, layout: WorkspaceLayout, selectedPanelID: UUID? = nil) {
        self.version = version
        self.layout = layout
        self.selectedPanelID = selectedPanelID
    }

    /// The panels currently rendering a terminal. Read from a document rather
    /// than from the store so a subscriber can ask it of the value it was
    /// handed, without waiting for the store's own property to settle.
    public var terminalPanelIDs: Set<UUID> {
        Set(layout.panels.compactMap { panel in
            if case .terminal = panel.kind { return panel.id }
            return nil
        })
    }

    public static func initial(homeFolder: String) -> WorkspaceDocument {
        let file = WorkspacePanel.file(at: homeFolder)
        let terminal = WorkspacePanel.terminal(linkedTo: file.id)
        return WorkspaceDocument(
            layout: .split(WorkspaceSplit(
                orientation: .vertical,
                ratio: 0.4,
                first: .panel(file),
                second: .panel(terminal)
            )),
            selectedPanelID: file.id
        )
    }
}
