import Foundation
import Testing
@testable import FolderTerminalCore

private final class TestBookmarkResolver: FolderBookmarkResolving {
    var resolvedURL: URL?
    var stale = false
    var shouldFail = false

    func makeBookmark(for url: URL) throws -> Data { Data(url.path.utf8) }

    func resolveBookmark(_ data: Data) throws -> (url: URL, isStale: Bool) {
        if shouldFail { throw CocoaError(.fileReadCorruptFile) }
        let fallback = URL(fileURLWithPath: String(decoding: data, as: UTF8.self))
        return (resolvedURL ?? fallback, stale)
    }
}

@Suite(.serialized)
@MainActor
struct WorkspaceStoreTests {
    @Test func bindingAndClosingFilePanelClearsBinding() {
        let root = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = makeStore(in: root)
        let file = WorkspacePanel.file(at: "/tmp")
        let terminal = WorkspacePanel.terminal(linkedTo: file.id)
        store.addPanel(file)
        store.addPanel(terminal)

        #expect(store.terminalsLinked(to: file.id).map(\.id) == [terminal.id])
        store.closePanel(id: file.id)
        guard let updated = store.panel(id: terminal.id), case .terminal(let state) = updated.kind else {
            Issue.record("Terminal missing")
            return
        }
        #expect(state.linkedFilePanelID == nil)
    }

    @Test func persistenceRoundTrip() {
        let root = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let saveURL = root.appendingPathComponent("workspace.json")
        let resolver = TestBookmarkResolver()
        let first = WorkspaceStore(persistenceURL: saveURL, bookmarkResolver: resolver)
        let panel = WorkspacePanel.file(at: root.path)
        first.addPanel(panel, orientation: .horizontal)
        first.select(panel.id)
        first.saveNow()

        let restored = WorkspaceStore(persistenceURL: saveURL, bookmarkResolver: resolver)
        #expect(restored.document == first.document)
    }

    @Test func environmentPinIsIndependentFromLinkAndReportedWorkingFolder() {
        let root = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = makeStore(in: root)
        let firstFolder = root.appendingPathComponent("first", isDirectory: true)
        let secondFolder = root.appendingPathComponent("second", isDirectory: true)
        let pinnedFolder = root.appendingPathComponent("pinned", isDirectory: true)
        try! FileManager.default.createDirectory(at: firstFolder, withIntermediateDirectories: true)
        try! FileManager.default.createDirectory(at: secondFolder, withIntermediateDirectories: true)
        try! FileManager.default.createDirectory(at: pinnedFolder, withIntermediateDirectories: true)
        let firstFile = WorkspacePanel.file(at: firstFolder.path)
        let secondFile = WorkspacePanel.file(at: secondFolder.path)
        let terminal = WorkspacePanel.terminal(linkedTo: firstFile.id)
        store.addPanel(firstFile)
        store.addPanel(secondFile)
        store.addPanel(terminal)

        try! store.pinFolder(pinnedFolder.path, for: terminal.id)
        store.bindTerminal(terminal.id, to: secondFile.id)
        store.reportWorkingFolder("/reported/by/shell", for: terminal.id)

        guard let updated = store.panel(id: terminal.id), case .terminal(let state) = updated.kind else {
            Issue.record("Terminal missing")
            return
        }
        #expect(state.linkedFilePanelID == secondFile.id)
        #expect(state.environmentFolder == pinnedFolder.path)
        #expect(state.lastWorkingFolder == "/reported/by/shell")

        store.unpinFolder(for: terminal.id)
        guard let unlocked = store.panel(id: terminal.id), case .terminal(let unlockedState) = unlocked.kind else {
            Issue.record("Terminal missing after unlock")
            return
        }
        #expect(unlockedState.environmentFolder == nil)
        #expect(unlockedState.lastWorkingFolder == "/reported/by/shell")
    }

    @Test func reportedWorkingFolderIsRuntimeOnly() throws {
        let root = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let saveURL = root.appendingPathComponent("workspace.json")
        let resolver = TestBookmarkResolver()
        let first = WorkspaceStore(persistenceURL: saveURL, bookmarkResolver: resolver)
        let terminal = try #require(first.panels.first { panel in
            if case .terminal = panel.kind { return true }
            return false
        })

        first.reportWorkingFolder("/runtime/only", for: terminal.id)
        first.saveNow()

        let savedJSON = try String(contentsOf: saveURL, encoding: .utf8)
        #expect(!savedJSON.contains("lastWorkingFolder"))
        #expect(!savedJSON.contains("/runtime/only"))

        let restored = WorkspaceStore(persistenceURL: saveURL, bookmarkResolver: resolver)
        guard let panel = restored.panel(id: terminal.id), case .terminal(let state) = panel.kind else {
            Issue.record("Missing restored terminal")
            return
        }
        #expect(state.lastWorkingFolder == nil)
    }

    @Test func pinningRejectsMissingFoldersWithoutChangingThePin() throws {
        let root = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let valid = root.appendingPathComponent("valid", isDirectory: true)
        try FileManager.default.createDirectory(at: valid, withIntermediateDirectories: true)
        let store = makeStore(in: root)
        let terminal = WorkspacePanel.terminal()
        store.addPanel(terminal)
        try store.pinFolder(valid.path, for: terminal.id)

        do {
            try store.pinFolder(root.appendingPathComponent("missing").path, for: terminal.id)
            Issue.record("Expected missing folder validation to fail")
        } catch let error as FolderValidationError {
            #expect(error == .missing(root.appendingPathComponent("missing").path))
        }

        guard let panel = store.panel(id: terminal.id), case .terminal(let state) = panel.kind else {
            Issue.record("Terminal missing")
            return
        }
        #expect(state.environmentFolder == valid.path)
    }

    @Test func disappearingPinnedFolderIsUnavailableButRemainsPinned() throws {
        let root = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let pinned = root.appendingPathComponent("pinned", isDirectory: true)
        try FileManager.default.createDirectory(at: pinned, withIntermediateDirectories: true)
        let store = makeStore(in: root)
        let terminal = WorkspacePanel.terminal()
        store.addPanel(terminal)
        try store.pinFolder(pinned.path, for: terminal.id)

        try FileManager.default.removeItem(at: pinned)

        #expect(!store.isFolderAvailable(at: pinned.path))
        #expect(store.folderValidationError(at: pinned.path) == .missing(pinned.path))
        guard let panel = store.panel(id: terminal.id), case .terminal(let state) = panel.kind else {
            Issue.record("Terminal missing")
            return
        }
        #expect(state.environmentFolder == pinned.path)
    }

    @Test func missingFolderRequestsReselectionWithoutLosingLayout() throws {
        let root = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("to-delete", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let saveURL = root.appendingPathComponent("workspace.json")
        let resolver = TestBookmarkResolver()
        let first = WorkspaceStore(persistenceURL: saveURL, bookmarkResolver: resolver)
        guard let fileID = first.filePanels.first?.id else {
            Issue.record("Missing file panel")
            return
        }
        try first.setFolder(folder, for: fileID)
        first.saveNow()
        try FileManager.default.removeItem(at: folder)

        resolver.shouldFail = true
        let restored = WorkspaceStore(persistenceURL: saveURL, bookmarkResolver: resolver)
        #expect(restored.document.layout.panelIDs.count == first.document.layout.panelIDs.count)
        guard let panel = restored.panel(id: fileID), case .file(let state) = panel.kind else {
            Issue.record("Missing restored file panel")
            return
        }
        #expect(state.requiresReselection)
    }

    private func makeStore(in root: URL) -> WorkspaceStore {
        WorkspaceStore(
            persistenceURL: root.appendingPathComponent("workspace.json"),
            bookmarkResolver: TestBookmarkResolver()
        )
    }

    private func temporaryFolder() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
