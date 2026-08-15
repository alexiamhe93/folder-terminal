import Foundation
import Testing
@testable import FolderTerminalCore

@Test func nestedSplitsAndRemovalCollapseTree() throws {
    let file = WorkspacePanel.file(at: "/tmp")
    let firstTerminal = WorkspacePanel.terminal(linkedTo: file.id)
    let secondTerminal = WorkspacePanel.terminal(linkedTo: file.id)
    var layout = WorkspaceLayout.panel(file)

    let firstSplitSucceeded = layout.splitPanel(
        id: file.id,
        orientation: .vertical,
        newPanel: firstTerminal
    )
    let secondSplitSucceeded = layout.splitPanel(
        id: firstTerminal.id,
        orientation: .horizontal,
        newPanel: secondTerminal
    )
    #expect(firstSplitSucceeded)
    #expect(secondSplitSucceeded)
    #expect(layout.panelIDs == [file.id, firstTerminal.id, secondTerminal.id])

    #expect(layout.removePanel(id: firstTerminal.id) == firstTerminal)
    #expect(layout.panelIDs == [file.id, secondTerminal.id])
    #expect(layout.panel(id: secondTerminal.id) != nil)
}

@Test func moveTransformationPreservesEveryPanel() {
    let a = WorkspacePanel.file(at: "/a")
    let b = WorkspacePanel.terminal()
    let c = WorkspacePanel.terminal()
    var layout = WorkspaceLayout.split(WorkspaceSplit(
        orientation: .vertical,
        first: .panel(a),
        second: .split(WorkspaceSplit(
            orientation: .horizontal,
            first: .panel(b),
            second: .panel(c)
        ))
    ))

    let moveSucceeded = layout.movePanel(id: c.id, beside: a.id, orientation: .horizontal)
    #expect(moveSucceeded)
    #expect(Set(layout.panelIDs) == Set([a.id, b.id, c.id]))
    #expect(layout.panelIDs.count == 3)
}

@Test func ratioIsClamped() throws {
    let a = WorkspacePanel.terminal()
    let b = WorkspacePanel.terminal()
    let splitID = UUID()
    var layout = WorkspaceLayout.split(WorkspaceSplit(
        id: splitID,
        orientation: .vertical,
        first: .panel(a),
        second: .panel(b)
    ))

    let updateSucceeded = layout.updateRatio(splitID: splitID, ratio: 2)
    #expect(updateSucceeded)
    guard case .split(let split) = layout else {
        Issue.record("Expected split")
        return
    }
    #expect(split.ratio == 0.9)
}

@Test func documentCodableRoundTrip() throws {
    let document = WorkspaceDocument.initial(homeFolder: "/Users/example")
    let data = try JSONEncoder().encode(document)
    #expect(try JSONDecoder().decode(WorkspaceDocument.self, from: data) == document)
}

@Test func initialTerminalIsLinkedButNotImplicitlyPinned() throws {
    let document = WorkspaceDocument.initial(homeFolder: "/Users/example")
    let terminal = try #require(document.layout.panels.first { panel in
        if case .terminal = panel.kind { return true }
        return false
    })
    guard case .terminal(let state) = terminal.kind else {
        Issue.record("Expected terminal")
        return
    }

    #expect(state.linkedFilePanelID != nil)
    #expect(state.environmentFolder == nil)
    #expect(state.lastWorkingFolder == nil)
}

@Test func terminalRuntimeFolderIsExcludedFromCodableState() throws {
    let state = TerminalPanelState(
        linkedFilePanelID: UUID(),
        environmentFolder: "/pinned",
        lastWorkingFolder: "/runtime"
    )
    let data = try JSONEncoder().encode(state)
    let json = String(decoding: data, as: UTF8.self)
    let restored = try JSONDecoder().decode(TerminalPanelState.self, from: data)

    #expect(!json.contains("lastWorkingFolder"))
    #expect(!json.contains("/runtime"))
    #expect(restored.linkedFilePanelID == state.linkedFilePanelID)
    #expect(restored.environmentFolder == "/pinned")
    #expect(restored.lastWorkingFolder == nil)
}

@Test func legacyPersistedWorkingFolderIsDiscarded() throws {
    let data = Data(#"{"environmentFolder":"/pinned","lastWorkingFolder":"/stale"}"#.utf8)
    let restored = try JSONDecoder().decode(TerminalPanelState.self, from: data)

    #expect(restored.environmentFolder == "/pinned")
    #expect(restored.lastWorkingFolder == nil)
}
