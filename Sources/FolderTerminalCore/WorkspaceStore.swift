import Combine
import Foundation

public enum FolderValidationError: LocalizedError, Equatable {
    case missing(String)
    case notDirectory(String)
    case unreadable(String)

    public var errorDescription: String? {
        switch self {
        case .missing(let path): return "The folder no longer exists: \(path)"
        case .notDirectory(let path): return "This location is not a folder: \(path)"
        case .unreadable(let path): return "The folder is not readable: \(path)"
        }
    }
}

public protocol FolderBookmarkResolving {
    func makeBookmark(for url: URL) throws -> Data
    func resolveBookmark(_ data: Data) throws -> (url: URL, isStale: Bool)
}

public struct SecurityScopedBookmarkResolver: FolderBookmarkResolving {
    public init() {}

    public func makeBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    public func resolveBookmark(_ data: Data) throws -> (url: URL, isStale: Bool) {
        var stale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        return (url, stale)
    }
}

@MainActor
public final class WorkspaceStore: ObservableObject {
    @Published public private(set) var document: WorkspaceDocument
    @Published public private(set) var persistenceError: String?

    public let persistenceURL: URL
    private let bookmarkResolver: FolderBookmarkResolving
    private let fileManager: FileManager
    private var saveWorkItem: DispatchWorkItem?
    private var accessedURLs: [URL] = []

    public init(
        persistenceURL: URL? = nil,
        fileManager: FileManager = .default,
        bookmarkResolver: FolderBookmarkResolving = SecurityScopedBookmarkResolver()
    ) {
        self.fileManager = fileManager
        self.bookmarkResolver = bookmarkResolver
        self.persistenceURL = persistenceURL ?? Self.defaultPersistenceURL(fileManager: fileManager)
        self.document = .initial(homeFolder: fileManager.homeDirectoryForCurrentUser.path)
        load()
    }

    deinit {
        for url in accessedURLs { url.stopAccessingSecurityScopedResource() }
    }

    public static func defaultPersistenceURL(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("FolderTerminal", isDirectory: true)
            .appendingPathComponent("workspace.json")
    }

    public var selectedPanelID: UUID? { document.selectedPanelID }
    public var panels: [WorkspacePanel] { document.layout.panels }
    public var filePanels: [WorkspacePanel] {
        panels.filter { if case .file = $0.kind { return true }; return false }
    }
    /// Panels currently rendering a terminal. The terminal registry uses this
    /// to decide which shells are still wanted — a panel that has been closed
    /// or replaced drops out of the set, and only then is its shell killed.
    public var terminalPanelIDs: Set<UUID> { document.terminalPanelIDs }

    public func panel(id: UUID) -> WorkspacePanel? { document.layout.panel(id: id) }

    public func select(_ id: UUID) {
        guard document.layout.panel(id: id) != nil else { return }
        document.selectedPanelID = id
        scheduleSave()
    }

    public func updatePanel(id: UUID, _ transform: (inout WorkspacePanel) -> Void) {
        guard document.layout.updatePanel(id: id, transform) else { return }
        objectWillChange.send()
        scheduleSave()
    }

    public func addPanel(_ panel: WorkspacePanel, orientation: SplitOrientation = .vertical) {
        guard let selected = document.selectedPanelID ?? document.layout.panelIDs.first else {
            document.layout = .panel(panel)
            document.selectedPanelID = panel.id
            scheduleSave()
            return
        }
        if document.layout.splitPanel(id: selected, orientation: orientation, newPanel: panel) {
            document.selectedPanelID = panel.id
            objectWillChange.send()
            scheduleSave()
        }
    }

    public func splitSelected(orientation: SplitOrientation, with panel: WorkspacePanel? = nil) {
        guard let selected = document.selectedPanelID else { return }
        let newPanel = panel ?? WorkspacePanel.terminal(linkedTo: nearestFilePanelID(to: selected))
        if document.layout.splitPanel(id: selected, orientation: orientation, newPanel: newPanel) {
            document.selectedPanelID = newPanel.id
            objectWillChange.send()
            scheduleSave()
        }
    }

    public func closePanel(id: UUID) {
        guard document.layout.panelIDs.count > 1 else { return }
        guard document.layout.removePanel(id: id) != nil else { return }
        if document.selectedPanelID == id { document.selectedPanelID = document.layout.panelIDs.first }
        removeBindings(to: id)
        objectWillChange.send()
        scheduleSave()
    }

    public func movePanel(id: UUID, beside targetID: UUID, orientation: SplitOrientation) {
        if document.layout.movePanel(id: id, beside: targetID, orientation: orientation) {
            document.selectedPanelID = id
            objectWillChange.send()
            scheduleSave()
        }
    }

    public func updateRatio(splitID: UUID, ratio: Double) {
        guard document.layout.updateRatio(splitID: splitID, ratio: ratio) else { return }
        objectWillChange.send()
        scheduleSave()
    }

    public func replacePanel(id: UUID, with kind: WorkspacePanelKind) {
        updatePanel(id: id) { $0.kind = kind }
    }

    public func bindTerminal(_ terminalID: UUID, to filePanelID: UUID?) {
        guard filePanelID == nil || filePanels.contains(where: { $0.id == filePanelID }) else { return }
        updatePanel(id: terminalID) { panel in
            guard case .terminal(var state) = panel.kind else { return }
            state.linkedFilePanelID = filePanelID
            panel.kind = .terminal(state)
        }
    }

    public func pinFolder(_ folder: String, for terminalID: UUID) throws {
        try pinFolder(folder, for: [terminalID])
    }

    public func pinFolder(_ folder: String, for terminalIDs: [UUID]) throws {
        try validateFolder(folder)
        for terminalID in terminalIDs {
            updatePanel(id: terminalID) { panel in
                guard case .terminal(var state) = panel.kind else { return }
                state.environmentFolder = folder
                panel.kind = .terminal(state)
            }
        }
    }

    public func unpinFolder(for terminalID: UUID) {
        updatePanel(id: terminalID) { panel in
            guard case .terminal(var state) = panel.kind else { return }
            state.environmentFolder = nil
            panel.kind = .terminal(state)
        }
    }

    public func reportWorkingFolder(_ folder: String, for terminalID: UUID) {
        guard document.layout.updatePanel(id: terminalID, { panel in
            guard case .terminal(var state) = panel.kind else { return }
            state.lastWorkingFolder = folder
            panel.kind = .terminal(state)
        }) else { return }
        objectWillChange.send()
    }

    public func folderValidationError(at path: String) -> FolderValidationError? {
        do {
            try validateFolder(path)
            return nil
        } catch let error as FolderValidationError {
            return error
        } catch {
            return .unreadable(path)
        }
    }

    public func isFolderAvailable(at path: String) -> Bool {
        folderValidationError(at: path) == nil
    }

    public func terminalsLinked(to filePanelID: UUID) -> [WorkspacePanel] {
        panels.filter {
            guard case .terminal(let state) = $0.kind else { return false }
            return state.linkedFilePanelID == filePanelID
        }
    }

    public func setFolder(_ url: URL, for panelID: UUID) throws {
        try validateFolder(url.path)
        let bookmark = try bookmarkResolver.makeBookmark(for: url)
        _ = url.startAccessingSecurityScopedResource()
        accessedURLs.append(url)
        updatePanel(id: panelID) { panel in
            guard case .file(var state) = panel.kind else { return }
            state.rootFolder = url.path
            state.currentFolder = url.path
            state.backHistory = []
            state.forwardHistory = []
            state.bookmark = bookmark
            state.requiresReselection = false
            panel.kind = .file(state)
        }
    }

    public func saveNow() {
        saveWorkItem?.cancel()
        do {
            let folder = persistenceURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(document).write(to: persistenceURL, options: .atomic)
            persistenceError = nil
        } catch {
            persistenceError = error.localizedDescription
        }
    }

    public func load() {
        guard fileManager.fileExists(atPath: persistenceURL.path) else { return }
        do {
            var restored = try JSONDecoder().decode(
                WorkspaceDocument.self,
                from: Data(contentsOf: persistenceURL)
            )
            restoreBookmarks(in: &restored.layout)
            if let selected = restored.selectedPanelID, restored.layout.panel(id: selected) == nil {
                restored.selectedPanelID = restored.layout.panelIDs.first
            }
            document = restored
            persistenceError = nil
        } catch {
            persistenceError = "Could not restore workspace: \(error.localizedDescription)"
        }
    }

    private func restoreBookmarks(in layout: inout WorkspaceLayout) {
        for panel in layout.panels {
            guard case .file(let state) = panel.kind else { continue }
            var resolvedURL: URL?
            var refreshedBookmark: Data?
            if let bookmark = state.bookmark,
               let result = try? bookmarkResolver.resolveBookmark(bookmark) {
                resolvedURL = result.url
                if result.isStale { refreshedBookmark = try? bookmarkResolver.makeBookmark(for: result.url) }
            }
            let candidate = resolvedURL ?? URL(fileURLWithPath: state.rootFolder)
            var isDirectory: ObjCBool = false
            let exists = fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory) && isDirectory.boolValue
            let beganSecurityScope = resolvedURL != nil && candidate.startAccessingSecurityScopedResource()
            // Unsandboxed personal builds can already read the URL, in which case
            // startAccessingSecurityScopedResource() is allowed to return false.
            let canAccess = resolvedURL == nil
                || beganSecurityScope
                || fileManager.isReadableFile(atPath: candidate.path)
            if beganSecurityScope { accessedURLs.append(candidate) }

            layout.updatePanel(id: panel.id) { updated in
                guard case .file(var fileState) = updated.kind else { return }
                if exists && canAccess {
                    fileState.rootFolder = candidate.path
                    if !fileManager.fileExists(atPath: fileState.currentFolder) {
                        fileState.currentFolder = candidate.path
                    }
                    if let refreshedBookmark { fileState.bookmark = refreshedBookmark }
                    fileState.requiresReselection = false
                } else {
                    fileState.requiresReselection = true
                }
                updated.kind = .file(fileState)
            }
        }
    }

    private func validateFolder(_ path: String) throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
            throw FolderValidationError.missing(path)
        }
        guard isDirectory.boolValue else {
            throw FolderValidationError.notDirectory(path)
        }
        guard fileManager.isReadableFile(atPath: path) else {
            throw FolderValidationError.unreadable(path)
        }
    }

    private func nearestFilePanelID(to id: UUID) -> UUID? {
        if let panel = panel(id: id), case .file = panel.kind { return id }
        return filePanels.first?.id
    }

    private func removeBindings(to filePanelID: UUID) {
        for terminal in panels {
            guard case .terminal(let state) = terminal.kind,
                  state.linkedFilePanelID == filePanelID else { continue }
            bindTerminal(terminal.id, to: nil)
        }
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: item)
    }
}
